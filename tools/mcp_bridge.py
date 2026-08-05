#!/usr/bin/env python3
"""Universal Hub MCP bridge -- gives an outside model the hub's own tools.

A Roblox executor cannot listen on a socket, so the hub cannot be the MCP
server. This is. It wears two faces at once:

  * to your MCP client (Claude Code, Cursor, anything) it is a normal stdio
    MCP server -- JSON-RPC on stdin/stdout;
  * to the hub it is a plain HTTP queue on 127.0.0.1:8421, which the hub
    polls a couple of times a second.

So a tools/call from the client parks a job here, the hub picks it up, runs
it inside the game, and posts the answer back. Both arrows point outward
from Roblox, which is the only shape that works from in there.

    claude mcp add universal-hub -- python3 /path/to/mcp_bridge.py

Every MCP client spawns its OWN copy of this file, so only the first one to
start can hold the port. That one owns the queue the game polls; the rest
find the port taken and become proxies, forwarding their clients' calls to
the owner over the same loopback interface. Binding unconditionally is what
made the second session die with EADDRINUSE the moment a first was running
-- and the client reads that as "Connection closed".

Nothing is stored and nothing is sent anywhere: the HTTP side binds to
loopback only, and the MCP side talks to the process that launched it.
"""

import json
import os
import queue
import urllib.error
import urllib.request
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8421
PROTOCOL = "2024-11-05"
VERSION = "1.1"
RAW = ("https://raw.githubusercontent.com/Angxers2/Unihubreborn/main/"
       "tools/mcp_bridge.py")

# The hub tells us what it has on every poll, so a tool added to the hub
# needs no change here. Empty until the game connects, which is also how we
# answer "is the hub actually there".
TOOLS: list = []
TOOLS_AT = 0.0

JOBS: "queue.Queue[dict]" = queue.Queue()
WAITING: dict = {}          # job id -> Event
RESULTS: dict = {}          # job id -> {"result"|"error": str}
LOCK = threading.Lock()
NEXT_ID = [0]

# A tool call runs inside a game that may be mid-teleport, and a gated one
# waits on a person noticing a prompt. Neither is fast.
CALL_TIMEOUT = 90
# How long after the last poll we still call the hub connected.
FRESH = 6
# Once the hub HAS connected, losing it for this long means the game is
# gone -- Roblox closed, or !mcp off -- and the bridge has nothing left to
# serve, so it stops rather than sitting there forever. A client that
# launched us will start us again the next time it needs a tool.
IDLE_EXIT = 120
SEEN_HUB = [False]
STOP = threading.Event()
# Whoever spoke initialize. Passed on to the hub so it can say "connected to
# Claude Code" rather than "connected", which is the difference between a
# toast that tells you something and one that just blinks.
CLIENT = [None]
# Whether this process holds the port. False means another copy does and
# we forward to it.
OWNER = [False]


def hub_online() -> bool:
    return (time.time() - TOOLS_AT) < FRESH


# ── the HTTP side: the hub polls this ───────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def _read(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return {}

    def _send(self, obj: dict):
        body = json.dumps(obj).encode("utf8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):  # noqa: N802  (http.server's naming)
        global TOOLS, TOOLS_AT
        path = self.path.split("?")[0]

        if path == "/poll":
            data = self._read()
            tools = data.get("tools")
            SEEN_HUB[0] = True
            if isinstance(tools, list) and tools:
                with LOCK:
                    TOOLS = tools
                    TOOLS_AT = time.time()
            else:
                TOOLS_AT = time.time()
            # Drained rather than popped one at a time: the hub can run a
            # handful in the time it takes to poll again.
            jobs = []
            while len(jobs) < 8:
                try:
                    jobs.append(JOBS.get_nowait())
                except queue.Empty:
                    break
            self._send({"jobs": jobs, "client": CLIENT[0], "version": VERSION})
            return

        if path == "/shutdown":
            # !mcp off, said directly rather than waited out.
            self._send({"ok": True})
            STOP.set()
            return

        if path == "/call":
            # A proxy handing over its client's call. Same path a local one
            # takes -- there is no second implementation of running a tool.
            d = self._read()
            text, bad = call_tool(d.get("tool") or "", d.get("args") or {})
            self._send({"error": text} if bad else {"result": text})
            return

        if path == "/results":
            for r in self._read().get("results") or []:
                jid = r.get("id")
                if jid is None:
                    continue
                with LOCK:
                    RESULTS[jid] = r
                    ev = WAITING.get(jid)
                if ev:
                    ev.set()
            self._send({"ok": True})
            return

        self.send_error(404, "no such path")

    def do_GET(self):  # noqa: N802
        if self.path.split("?")[0] == "/tools":
            with LOCK:
                self._send({"tools": list(TOOLS)})
            return
        if self.path.split("?")[0] == "/health":
            # Answering at all IS the answer to "is the bridge installed and
            # running" -- the hub has no other way to look.
            self._send({"ok": True, "hub": hub_online(), "tools": len(TOOLS),
                        "client": CLIENT[0], "version": VERSION})
            return
        self.send_error(404, "no such path")

    def log_message(self, fmt, *args):
        pass  # stdout belongs to the MCP protocol


# ── the MCP side: stdio JSON-RPC ────────────────────────────────────────
def call_tool(name: str, args: dict) -> tuple[str, bool]:
    """Queue a call for the hub and wait. Returns (text, is_error)."""
    if not hub_online():
        return ("The Universal Hub is not connected. Run !mcp on inside the "
                "game -- the bridge is up but nothing is listening from Roblox.",
                True)

    with LOCK:
        NEXT_ID[0] += 1
        jid = NEXT_ID[0]
        ev = threading.Event()
        WAITING[jid] = ev
    JOBS.put({"id": jid, "tool": name, "args": args})

    if not ev.wait(CALL_TIMEOUT):
        with LOCK:
            WAITING.pop(jid, None)
        return ("The hub did not answer in %ds. It may be mid-teleport, or "
                "waiting on the user to approve the call." % CALL_TIMEOUT, True)

    with LOCK:
        WAITING.pop(jid, None)
        r = RESULTS.pop(jid, {})
    if "error" in r:
        return (str(r["error"]), True)
    return (str(r.get("result", "done")), False)


# ── proxy side: another copy holds the port ─────────────────────────────
def ask_owner(path: str, obj=None, timeout: float = 10):
    url = "http://127.0.0.1:%d%s" % (PORT, path)
    data = json.dumps(obj).encode("utf8") if obj is not None else None
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def take_over() -> bool:
    """The owner has gone. Try to become it rather than staying broken."""
    srv = bind()
    if not srv:
        return False
    OWNER[0] = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    threading.Thread(target=watchdog, daemon=True).start()
    threading.Thread(target=lambda: (STOP.wait(), srv.shutdown()), daemon=True).start()
    print("universal-hub bridge: took the port over from a bridge that left",
          file=sys.stderr)
    return True


def list_tools() -> list:
    if OWNER[0]:
        with LOCK:
            return list(TOOLS)
    try:
        return ask_owner("/tools", timeout=5).get("tools") or []
    except (urllib.error.URLError, OSError, ValueError):
        # The owner went away mid-session. Becoming it is better than
        # reporting an empty toolbox for the rest of this one.
        if take_over():
            with LOCK:
                return list(TOOLS)
        return []


def run_tool(name: str, args: dict) -> tuple[str, bool]:
    if OWNER[0]:
        return call_tool(name, args)
    try:
        d = ask_owner("/call", {"tool": name, "args": args},
                      timeout=CALL_TIMEOUT + 10)
    except (urllib.error.URLError, OSError, ValueError) as e:
        if take_over():
            return call_tool(name, args)
        return ("The bridge holding the queue went away: %s" % e, True)
    if "error" in d:
        return (str(d["error"]), True)
    return (str(d.get("result", "done")), False)


def rpc(msg: dict):
    """Answer one JSON-RPC message. Returns a reply dict, or None."""
    method = msg.get("method")
    mid = msg.get("id")

    if method == "initialize":
        info = (msg.get("params") or {}).get("clientInfo") or {}
        name = info.get("name")
        if isinstance(name, str) and name.strip():
            v = info.get("version")
            CLIENT[0] = name.strip() + (" " + str(v) if isinstance(v, str) and v else "")
        return {
            "jsonrpc": "2.0", "id": mid,
            "result": {
                "protocolVersion": PROTOCOL,
                "capabilities": {"tools": {"listChanged": True}},
                "serverInfo": {"name": "universal-hub", "version": "1.0.0"},
            },
        }

    # Notifications carry no id and take no reply.
    if mid is None:
        return None

    if method == "tools/list":
        tools = list_tools()
        if not tools:
            # Better than an empty list: the client shows the reason.
            tools = [{
                "name": "hub_not_connected",
                "description": ("The Universal Hub has not connected to this "
                                "bridge yet. Run !mcp on inside the game, then "
                                "list tools again."),
                "inputSchema": {"type": "object"},
            }]
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}}

    if method == "tools/call":
        p = msg.get("params") or {}
        text, bad = run_tool(p.get("name") or "", p.get("arguments") or {})
        return {
            "jsonrpc": "2.0", "id": mid,
            "result": {"content": [{"type": "text", "text": text}],
                       "isError": bad},
        }

    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}

    return {"jsonrpc": "2.0", "id": mid,
            "error": {"code": -32601, "message": "no method %r" % method}}


def serve_stdio():
    out = sys.stdout
    for line in sys.stdin:
        if STOP.is_set():
            return
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            reply = rpc(msg)
        except Exception as e:  # a bad call must not take the server down
            reply = {"jsonrpc": "2.0", "id": msg.get("id"),
                     "error": {"code": -32603, "message": str(e)}}
        if reply is not None:
            out.write(json.dumps(reply) + "\n")
            out.flush()


def watchdog():
    """Stop once the game has been gone a while, having once been here."""
    while not STOP.wait(5):
        if OWNER[0] and SEEN_HUB[0] and (time.time() - TOOLS_AT) > IDLE_EXIT:
            print("universal-hub bridge: hub gone for %ds, stopping" % IDLE_EXIT,
                  file=sys.stderr)
            STOP.set()
            return


def self_update():
    """Fetch the published bridge and keep it for next launch, if it moved.

    Written, not executed. Replacing the file under a running session and
    re-exec'ing would drop the client's connection mid-conversation to fix
    something that is not yet broken -- so the new copy is put in place and
    starts being used the next time the client launches it, which it does
    every session anyway.

    Set UHUB_MCP_NO_UPDATE to keep a copy you are editing.
    """
    if os.environ.get("UHUB_MCP_NO_UPDATE"):
        return
    try:
        with urllib.request.urlopen(RAW, timeout=10) as r:
            new = r.read()
    except (urllib.error.URLError, OSError, ValueError):
        return  # offline is not an error worth saying anything about
    # It has to look like this program before it is allowed to become it.
    if len(new) < 4000 or b"universal-hub bridge" not in new:
        return
    here = os.path.abspath(__file__)
    try:
        if open(here, "rb").read() == new:
            return
        with open(here, "wb") as f:
            f.write(new)
    except OSError:
        return
    print("universal-hub bridge: a newer bridge was published and has been "
          "written to %s -- it takes effect next time your client starts it"
          % here, file=sys.stderr)


def bind():
    """The port, or None when another copy of this file already has it."""
    try:
        return ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as e:
        # 48 on BSD/macOS, 98 on Linux, 10048 on Windows.
        if e.errno in (48, 98, 10048):
            return None
        raise


def main():
    srv = bind()
    if srv:
        OWNER[0] = True
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        threading.Thread(target=watchdog, daemon=True).start()
        threading.Thread(target=lambda: (STOP.wait(), srv.shutdown()),
                         daemon=True).start()
        # Never print to stdout here -- it is the protocol channel.
        print("universal-hub bridge: %s, MCP on stdio, hub queue on "
              "127.0.0.1:%d" % (VERSION, PORT), file=sys.stderr)
        # Only the owner checks: every client spawns a copy, and three of
        # them fetching the same file on every launch is noise.
        threading.Thread(target=self_update, daemon=True).start()
    else:
        # Another copy owns the queue. Serve this client by forwarding to
        # it, rather than exiting -- which is what the client sees as
        # "Connection closed".
        print("universal-hub bridge: another bridge holds 127.0.0.1:%d, "
              "forwarding to it" % PORT, file=sys.stderr)
    try:
        serve_stdio()
        # stdin ended. Launched by an MCP client that means the client is
        # gone; run straight from a terminal with stdin backgrounded or
        # redirected it means there was never a client at all -- and the
        # hub still needs the queue. Exiting here is what made a bridge
        # started with & or nohup print the banner and die.
        if not STOP.is_set():
            print("universal-hub bridge: no MCP client on stdin, serving the "
                  "hub queue only", file=sys.stderr)
            STOP.wait()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

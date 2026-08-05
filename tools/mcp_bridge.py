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

Nothing is stored and nothing is sent anywhere: the HTTP side binds to
loopback only, and the MCP side talks to the process that launched it.
"""

import json
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8421
PROTOCOL = "2024-11-05"

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
            self._send({"jobs": jobs, "client": CLIENT[0]})
            return

        if path == "/shutdown":
            # !mcp off, said directly rather than waited out.
            self._send({"ok": True})
            STOP.set()
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
        if self.path.split("?")[0] == "/health":
            # Answering at all IS the answer to "is the bridge installed and
            # running" -- the hub has no other way to look.
            self._send({"ok": True, "hub": hub_online(), "tools": len(TOOLS),
                        "client": CLIENT[0]})
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
        with LOCK:
            tools = list(TOOLS)
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
        text, bad = call_tool(p.get("name") or "", p.get("arguments") or {})
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
        if SEEN_HUB[0] and (time.time() - TOOLS_AT) > IDLE_EXIT:
            print("universal-hub bridge: hub gone for %ds, stopping" % IDLE_EXIT,
                  file=sys.stderr)
            STOP.set()
            return


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    threading.Thread(target=watchdog, daemon=True).start()
    threading.Thread(target=lambda: (STOP.wait(), srv.shutdown()), daemon=True).start()
    # Never print to stdout here -- it is the protocol channel.
    print("universal-hub bridge: MCP on stdio, hub queue on 127.0.0.1:%d" % PORT,
          file=sys.stderr)
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

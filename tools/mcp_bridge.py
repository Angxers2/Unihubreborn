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
import secrets
import urllib.error
import urllib.request
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8421
PROTOCOL = "2024-11-05"
VERSION = "1.6"
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
# serve_stdio and the list_changed notifier both write to stdout, and two
# interleaved JSON lines are two corrupt messages.
OUT_LOCK = threading.Lock()

# Loopback is not a boundary. Any page the user visits can fetch() a
# 127.0.0.1 URL, so an endpoint that RUNS something needs to prove the
# caller is one of ours. A proxy is a different process and cannot read the
# owner's memory, so the secret goes in a file only the user can read --
# which a web page cannot do.
TOKEN_PATH = os.path.join(os.path.expanduser("~"), ".uhub_mcp_token")


def shared_token() -> str:
    try:
        if os.path.exists(TOKEN_PATH):
            t = open(TOKEN_PATH, encoding="utf8").read().strip()
            if t:
                return t
    except OSError:
        pass
    t = secrets.token_hex(16)
    try:
        fd = os.open(TOKEN_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(t)
    except OSError:
        pass  # unwritable home: the token is still consistent in-process
    return t


TOKEN = shared_token()


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

    def _bad_host(self) -> bool:
        """A request that did not address this machine by name.

        DNS rebinding works by pointing a hostname the browser trusts at
        127.0.0.1; the connection arrives here carrying THAT name in Host.
        Checking it is the standard guard, and it costs one comparison.
        """
        h = (self.headers.get("Host") or "").lower()
        return h not in ("127.0.0.1:%d" % PORT, "localhost:%d" % PORT,
                         "[::1]:%d" % PORT)

    def _from_browser(self) -> bool:
        """Did a page send this? Browsers attach these; HTTP libraries do not.

        This is what stops a site the user happens to be visiting from
        driving their game through the loopback port.
        """
        h = self.headers
        return bool(h.get("Origin") or h.get("Sec-Fetch-Mode")
                    or h.get("Sec-Fetch-Site"))

    def do_POST(self):  # noqa: N802  (http.server's naming)
        global TOOLS, TOOLS_AT
        path = self.path.split("?")[0]

        if self._from_browser() or self._bad_host():
            self.send_error(403, "not reachable from a page")
            return

        if path == "/poll":
            data = self._read()
            tools = data.get("tools")
            SEEN_HUB[0] = True
            if isinstance(tools, list) and tools:
                with LOCK:
                    had = len(TOOLS)
                    TOOLS = tools
                    TOOLS_AT = time.time()
                # We advertise listChanged, so we owe the client this. Going
                # from the hub_not_connected placeholder to a real list
                # without saying so is what strands a session that listed
                # tools before the game connected -- it keeps the placeholder
                # forever, and no amount of !mcp on changes what it sees.
                if had == 0 and tools:
                    notify_list_changed()
            else:
                TOOLS_AT = time.time()
            # Drained rather than popped one at a time: the hub can run a
            # handful in the time it takes to poll again.
            jobs = []
            while len(jobs) < 8:
                try:
                    j = JOBS.get_nowait()
                except queue.Empty:
                    break
                # Queued before the hub dropped and drained after it came
                # back is a call running minutes late, possibly in a
                # different game. Its caller gave up long ago.
                if time.time() - j.get("at", 0) > CALL_TIMEOUT:
                    continue
                jobs.append(j)
            self._send({"jobs": jobs, "client": CLIENT[0], "version": VERSION})
            return

        if path == "/shutdown":
            # !mcp off, said directly rather than waited out.
            self._send({"ok": True})
            STOP.set()
            return

        if path == "/spotify":
            # Some executors -- MacSploit is one -- rewrite PUT as POST on
            # the wire. Spotify answers 405 to every play, pause, volume and
            # like as a result, and no header talks it out of that. Python's
            # PUT is a PUT, so the hub hands the request here instead.
            #
            # Deliberately Spotify-only: a general relay on a loopback port
            # is an SSRF hole, and this needs exactly one host.
            d = self._read()
            p = str(d.get("path") or "")
            method = str(d.get("method") or "GET").upper()
            if not p.startswith("/") or method not in ("PUT", "DELETE", "POST", "GET"):
                self.send_error(400, "bad relay request")
                return
            body = d.get("body")
            req = urllib.request.Request(
                "https://api.spotify.com/v1" + p,
                data=body.encode("utf8") if isinstance(body, str) else None,
                method=method,
                headers={"Authorization": str(d.get("auth") or ""),
                         "Content-Type": "application/json"},
            )
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    self._send({"code": r.status,
                                "body": r.read().decode("utf8", "replace")})
            except urllib.error.HTTPError as e:
                # Spotify's own 4xx is an answer, not a failure -- the hub
                # reads its message and shows it.
                self._send({"code": e.code,
                            "body": e.read().decode("utf8", "replace")})
            except Exception as e:  # noqa: BLE001  (network, any reason)
                self._send({"code": 0, "body": str(e)[:200]})
            return

        if path == "/call":
            # A proxy handing over its client's call. Same path a local one
            # takes -- there is no second implementation of running a tool.
            # It is the one endpoint that EXECUTES, so it is the one that
            # has to prove who is asking.
            if not secrets.compare_digest(
                    self.headers.get("X-UHub-Token") or "", TOKEN):
                self.send_error(401, "bad or missing token")
                return
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
                    ev = WAITING.get(jid)
                    # A late answer to a call that already timed out has
                    # nobody to give it to, and keeping it grows RESULTS
                    # for the life of the process.
                    if ev is None:
                        continue
                    RESULTS[jid] = r
                ev.set()
            self._send({"ok": True})
            return

        self.send_error(404, "no such path")

    def do_GET(self):  # noqa: N802
        if self._from_browser() or self._bad_host():
            self.send_error(403, "not reachable from a page")
            return
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
    JOBS.put({"id": jid, "tool": name, "args": args, "at": time.time()})

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
def say(msg: dict):
    """One JSON line on stdout, under the lock that keeps them whole.

    Never raises. This is called from the HTTP threads as well as the MCP
    one, and when no client is attached -- the bridge serving the hub queue
    on its own -- stdout is a closed pipe. That was killing the /poll thread
    with a BrokenPipeError traceback the moment the hub's tools first
    arrived, because that is when the listChanged notice goes out.
    """
    try:
        with OUT_LOCK:
            sys.stdout.write(json.dumps(msg) + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, ValueError, OSError):
        pass


def notify_list_changed():
    say({"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})


def watch_tools():
    """A proxy has no /poll of its own, so it watches the owner's count."""
    seen = 0
    while not STOP.wait(1.5):
        if OWNER[0]:
            return  # the owner notifies from /poll, where it learns first
        try:
            n = ask_owner_get("/health", timeout=3).get("tools") or 0
        except (urllib.error.URLError, OSError, ValueError):
            continue
        if n and not seen:
            notify_list_changed()
        seen = n


def ask_owner(path: str, obj=None, timeout: float = 10):
    url = "http://127.0.0.1:%d%s" % (PORT, path)
    data = json.dumps(obj).encode("utf8") if obj is not None else None
    req = urllib.request.Request(url, data=data, headers={
        "Content-Type": "application/json",
        "X-UHub-Token": TOKEN,
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def ask_owner_get(path: str, timeout: float = 5):
    req = urllib.request.Request(
        "http://127.0.0.1:%d%s" % (PORT, path),
        headers={"X-UHub-Token": TOKEN})
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


# ── the one tool the game cannot do ─────────────────────────────────────
# Roblox will not give a client script a picture of itself. CaptureService
# hands back an rbxtemp:// id whose bytes no client API can read, several
# executors refuse the call outright as a "malicious function", and Infinite
# Yield's screenshot command just asks Roblox to save one to the user's
# Pictures folder -- nothing comes back to the script either way.
#
# The bridge is a native process looking at the same screen, so it takes the
# picture here instead. This never touches the game, and the model gets a
# real image rather than a description of one.
SHOT_TOOL = {
    "name": "screenshot",
    "description": (
        "Take a picture of the screen the game is running on and return it as "
        "an image. Use it to SEE what is happening -- the UI, where the "
        "character is, what a menu says -- when the text tools cannot answer. "
        "This captures the whole display, not just Roblox, so treat it the way "
        "you would treat looking over somebody's shoulder."),
    "inputSchema": {
        "type": "object",
        "properties": {
            "width": {"type": "number",
                      "description": "Longest edge in pixels, 320-1920. Default 1280."},
            "why": {"type": "string",
                    "description": "One line the user sees in-game saying what "
                                   "you are looking for."},
        },
    },
}


def _shot_file(path: str, width: int) -> str:
    """Capture the screen to `path` as JPEG. Returns '' on success, else why."""
    import shutil
    import subprocess
    # Coerced, not trusted. A model that passes "1280" or "big" should get a
    # screenshot, not a stack trace about int().
    try:
        px = int(float(width))
    except (TypeError, ValueError):
        px = 1280
    w = str(max(320, min(1920, px)))

    if sys.platform == "darwin":
        raw = path + ".png"
        # -x: no shutter sound. Taking a picture is quiet enough already
        # without announcing it to whoever is in the room.
        r = subprocess.run(["screencapture", "-x", "-t", "png", raw],
                           capture_output=True, timeout=20)
        if r.returncode != 0 or not os.path.exists(raw):
            return "screencapture failed: " + r.stderr.decode()[:120]
        # Down to something a model can look at without a megabyte of base64
        # travelling for every glance.
        subprocess.run(["sips", "-Z", w, "-s", "format", "jpeg",
                        "-s", "formatOptions", "70", raw, "--out", path],
                       capture_output=True, timeout=20)
        try:
            os.remove(raw)
        except OSError:
            pass
        return "" if os.path.exists(path) else "sips produced nothing"

    if sys.platform.startswith("win"):
        ps = (
            "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;"
            "$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds;"
            "$bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height;"
            "$g=[System.Drawing.Graphics]::FromImage($bmp);"
            "$g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size);"
            "$sc=%s/[double]$b.Width; if($sc -gt 1){$sc=1};"
            "$nw=[int]($b.Width*$sc); $nh=[int]($b.Height*$sc);"
            "$out=New-Object System.Drawing.Bitmap $nw,$nh;"
            "$g2=[System.Drawing.Graphics]::FromImage($out);"
            "$g2.InterpolationMode='HighQualityBicubic';"
            "$g2.DrawImage($bmp,0,0,$nw,$nh);"
            "$c=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|"
            "Where-Object{$_.MimeType -eq 'image/jpeg'};"
            "$p=New-Object System.Drawing.Imaging.EncoderParameters 1;"
            "$p.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter "
            "([System.Drawing.Imaging.Encoder]::Quality,70);"
            "$out.Save('%s',$c,$p);"
        ) % (w, path.replace("\\", "\\\\"))
        r = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                           capture_output=True, timeout=30)
        if not os.path.exists(path):
            return "powershell capture failed: " + r.stderr.decode()[:120]
        return ""

    # Linux: whichever of these is installed. grim is Wayland, the rest X11.
    for cmd in (["grim", path], ["scrot", "-o", path],
                ["import", "-window", "root", path],
                ["gnome-screenshot", "-f", path]):
        if shutil.which(cmd[0]):
            subprocess.run(cmd, capture_output=True, timeout=20)
            if os.path.exists(path):
                return ""
    return ("no screenshot tool found -- install grim, scrot, imagemagick or "
            "gnome-screenshot")


def take_shot(args: dict) -> tuple[str, str]:
    """Returns (base64_jpeg, '') or ('', why_it_failed)."""
    import base64
    import tempfile
    fd, path = tempfile.mkstemp(suffix=".jpg")
    os.close(fd)
    try:
        why = _shot_file(path, args.get("width") or 1280)
        if why:
            return "", why
        with open(path, "rb") as f:
            raw = f.read()
        if not raw:
            return "", "the capture came back empty"
        return base64.b64encode(raw).decode("ascii"), ""
    except Exception as e:  # noqa: BLE001  (a screenshot must never take the bridge down)
        return "", "%s: %s" % (type(e).__name__, str(e)[:120])
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


def list_tools() -> list:
    if OWNER[0]:
        with LOCK:
            # The screenshot is ours, not the hub's, so it is offered even
            # while the game is still connecting -- looking at the screen is
            # exactly what you want when the game is not answering.
            return list(TOOLS) + [SHOT_TOOL]
    try:
        return (ask_owner("/tools", timeout=5).get("tools") or []) + [SHOT_TOOL]
    except (urllib.error.URLError, OSError, ValueError):
        # The owner went away mid-session. Becoming it is better than
        # reporting an empty toolbox for the rest of this one.
        if take_over():
            with LOCK:
                return list(TOOLS) + [SHOT_TOOL]
        return [SHOT_TOOL]


def run_tool(name: str, args: dict) -> tuple[str, bool]:
    if name == "screenshot":
        # Handled here, never queued: the game has no way to take one, and
        # forwarding it would just time out against a tool the hub does not
        # have. rpc() picks the image up separately.
        return ("screenshot", False)
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
        params = msg.get("params") or {}
        # Answer in the version they asked for when we understand it, rather
        # than insisting on ours and hoping they cope.
        want = params.get("protocolVersion")
        proto = want if isinstance(want, str) and want else PROTOCOL
        info = params.get("clientInfo") or {}
        name = info.get("name")
        if isinstance(name, str) and name.strip():
            v = info.get("version")
            CLIENT[0] = name.strip() + (" " + str(v) if isinstance(v, str) and v else "")
        return {
            "jsonrpc": "2.0", "id": mid,
            "result": {
                "protocolVersion": proto,
                "capabilities": {"tools": {"listChanged": True}},
                "serverInfo": {"name": "universal-hub", "version": VERSION},
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
        name = p.get("name") or ""
        args = p.get("arguments") or {}

        if name == "screenshot":
            b64, why = take_shot(args)
            if why:
                return {"jsonrpc": "2.0", "id": mid,
                        "result": {"content": [{"type": "text",
                                                "text": "No screenshot: " + why}],
                                   "isError": True}}
            # Say so in the game. A picture of somebody's screen is taken
            # WITH them, not of them, and the notification is the difference.
            why_txt = str(args.get("why") or "")[:120]
            def _tell():
                # Best effort: the picture has already been taken, and a hub
                # that is not there must not turn that into an error.
                try:
                    call_tool("notify", {
                        "title": "Screenshot",
                        "text": why_txt or "The model looked at your screen",
                        "kind": "info",
                    })
                except Exception:  # noqa: BLE001
                    pass

            threading.Thread(target=_tell, daemon=True).start()
            return {"jsonrpc": "2.0", "id": mid,
                    "result": {"content": [{"type": "image", "data": b64,
                                            "mimeType": "image/jpeg"}],
                               "isError": False}}

        text, bad = run_tool(name, args)
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
            say(reply)


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
    # It has to be a program before it is allowed to become this one. A
    # substring check would let a truncated publish through, and the only
    # symptom on the far end is "Connection closed" with no cause.
    try:
        compile(new, "<update>", "exec")
    except (SyntaxError, ValueError):
        print("universal-hub bridge: the published bridge does not compile, "
              "keeping this one", file=sys.stderr)
        return
    # ...and it has to be NEWER. raw.githubusercontent serves the previous
    # copy for a minute or so after a push, so writing whatever it returns
    # means a fresh install can be quietly rolled BACK to the version it
    # just replaced -- which is exactly what happened to 1.5.
    import re as _re
    m = _re.search(rb'^VERSION = "([0-9.]+)"', new, _re.M)
    if not m:
        return
    def _v(t):
        return tuple(int(x) for x in t.split(".") if x.isdigit())
    if _v(m.group(1).decode()) <= _v(VERSION):
        return
    here = os.path.abspath(__file__)
    try:
        if open(here, "rb").read() == new:
            return
        # Written beside it and moved into place: truncate-then-write leaves
        # half a file if the machine sleeps mid-write, and half a file is a
        # bridge that never starts again.
        tmp = here + ".new"
        with open(tmp, "wb") as f:
            f.write(new)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, here)
    except OSError:
        try:
            os.unlink(here + ".new")
        except OSError:
            pass
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
        threading.Thread(target=watch_tools, daemon=True).start()
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

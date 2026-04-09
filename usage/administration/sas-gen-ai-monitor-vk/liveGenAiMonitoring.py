#!/usr/bin/env python3
# A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
# DATE: 06APR2026
#
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
liveGenAiMonitoring.py -- Viya4 GenAI Monitor (local build)

Local-only version: no kubectl, no kubeconfig, no pyyaml needed.
Only requires Python 3.8+ standard library.

Usage:
  python3 liveGenAiMonitoring.py
  python3 liveGenAiMonitoring.py --port 8899
"""

import argparse
import base64
import gzip
import json
import ssl
import subprocess
import threading
import urllib.request
import urllib.parse
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib     import Path
from socketserver import ThreadingMixIn

SSL_CTX        = ssl._create_unverified_context()
DASHBOARD_HTML = Path(__file__).parent / "viya4_dashboard.html"
CACHE_DIR      = Path(__file__).parent / "cache"

# -- Cache filename helper ----------------------------------------------------
def _cache_filename(cluster: str, user: str) -> Path:
    import re
    safe = re.sub(r"[^a-z0-9._-]", "_", (cluster + "__" + user).lower())
    return CACHE_DIR / (safe + ".json")

# -- Dashboard cache: read once from disk, serve many times --------------------
_dash_cache = {"data": None, "mtime": 0.0}
_dash_lock  = threading.Lock()

def get_dashboard():
    if not DASHBOARD_HTML.exists():
        return b"<h1>viya4_dashboard.html not found</h1>"
    mtime = DASHBOARD_HTML.stat().st_mtime
    with _dash_lock:
        if _dash_cache["mtime"] != mtime:
            _dash_cache["data"]  = DASHBOARD_HTML.read_bytes()
            _dash_cache["mtime"] = mtime
    return _dash_cache["data"]

# -- Threaded server: each request handled in its own thread ------------------
class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


# -----------------------------------------------------------------------------
class ProxyHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print("  %s -- %s" % (self.address_string(), fmt % args))

    def send_json(self, code, obj, compress=False):
        body = json.dumps(obj, separators=(",", ":")).encode()
        enc  = self.headers.get("Accept-Encoding", "")
        if compress and len(body) > 4096 and "gzip" in enc:
            body = gzip.compress(body, compresslevel=6)
            self.send_response(code)
            self.send_header("Content-Encoding", "gzip")
        else:
            self.send_response(code)
        self.send_header("Content-Type",   "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Connection",     "keep-alive")
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, code, html):
        self.send_response(code)
        self.send_header("Content-Type",   "text/html; charset=utf-8")
        self.send_header("Content-Length", len(html))
        self.send_header("Cache-Control",  "no-cache")
        self.end_headers()
        self.wfile.write(html)

    def read_json(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n)) if n else {}

    # -- Routes ----------------------------------------------------------------
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self.send_html(200, get_dashboard())
        elif path == "/health":
            self.send_json(200, {"status": "ok"})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        try:
            payload = self.read_json()
        except Exception:
            self.send_json(400, {"error": "invalid JSON"}); return

        # -- /api/token --------------------------------------------------------
        if path == "/api/token":
            viya_url = payload.get("url", "").rstrip("/")
            username = payload.get("username", "")
            password = payload.get("password", "")
            if not all([viya_url, username, password]):
                self.send_json(400, {"error": "url, username and password are required"}); return
            try:
                data = urllib.parse.urlencode({
                    "grant_type": "password",
                    "username":   username,
                    "password":   password,
                }).encode()
                req = urllib.request.Request(
                    "%s/SASLogon/oauth/token" % viya_url,
                    data=data,
                    headers={
                        "Content-Type":  "application/x-www-form-urlencoded",
                        "Authorization": "Basic " + base64.b64encode(b"sas.cli:").decode(),
                    },
                    method="POST",
                )
                with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as r:
                    self.send_json(200, json.loads(r.read()))
            except urllib.error.HTTPError as e:
                self.send_json(e.code, {"error": e.read().decode(errors="replace")})
            except Exception as e:
                self.send_json(502, {"error": str(e)})
            return

        # -- /api/proxy --------------------------------------------------------
        if path == "/api/proxy":
            viya_url = payload.get("url", "").rstrip("/")
            api_path = payload.get("path", "")
            bearer   = payload.get("token", "")
            method   = payload.get("method", "GET").upper()
            req_body = payload.get("body", None)
            if not api_path:
                self.send_json(400, {"error": "missing path"}); return
            px_headers = {
                "Authorization": "Bearer %s" % bearer,
                "Accept":        "application/vnd.sas.collection+json",
            }
            if req_body:
                px_headers["Content-Type"] = "application/json"
            try:
                req = urllib.request.Request(
                    "%s%s" % (viya_url, api_path),
                    data=json.dumps(req_body).encode() if req_body else None,
                    headers=px_headers, method=method,
                )
                with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as r:
                    self.send_json(200, json.loads(r.read()))
            except urllib.error.HTTPError as e:
                self.send_json(e.code, {"error": e.read().decode(errors="replace")})
            except Exception as e:
                self.send_json(502, {"error": str(e)})
            return

        # -- /api/proxy-all: fetch all pages in parallel, return merged --------
        if path == "/api/proxy-all":
            viya_url  = payload.get("url", "").rstrip("/")
            api_path  = payload.get("path", "")
            bearer    = payload.get("token", "")
            page_size = int(payload.get("limit", 100))
            if not api_path:
                self.send_json(400, {"error": "missing path"}); return

            req_headers = {
                "Authorization": "Bearer %s" % bearer,
                "Accept":        "application/vnd.sas.collection+json",
            }
            sep = "&" if "?" in api_path else "?"
            base_url = "%s%s%slimit=%d&start=" % (viya_url, api_path, sep, page_size)

            def fetch_page(start):
                with urllib.request.urlopen(
                    urllib.request.Request(base_url + str(start), headers=req_headers),
                    context=SSL_CTX, timeout=20
                ) as r:
                    return json.loads(r.read())

            try:
                first  = fetch_page(0)
                total  = first.get("count", len(first.get("items", [])))
                result = list(first.get("items", []))
                print("  [proxy-all] %s  total=%d" % (api_path, total))

                if total > page_size:
                    starts = range(page_size, total, page_size)
                    with ThreadPoolExecutor(max_workers=min(8, len(list(starts)))) as pool:
                        futures = {pool.submit(fetch_page, s): s for s in starts}
                        pages   = {}
                        for f in as_completed(futures):
                            pages[futures[f]] = f.result().get("items", [])
                        for s in sorted(pages):
                            result.extend(pages[s])

                self.send_json(200, {
                    "count": len(result), "start": 0,
                    "limit": len(result), "items": result,
                }, compress=True)

            except urllib.error.HTTPError as e:
                self.send_json(e.code, {"error": e.read().decode(errors="replace")})
            except Exception as e:
                self.send_json(502, {"error": str(e)})
            return

        # -- /api/cache: server-side persistent chat cache per cluster+user --------
        if path == "/api/cache":
            action  = payload.get("action", "")
            cluster = payload.get("cluster", "").lower().replace("https://","").replace("http://","").rstrip("/")
            user    = payload.get("user", "").lower()
            if not cluster or not user:
                self.send_json(400, {"error": "cluster and user are required"}); return
            cf = _cache_filename(cluster, user)
            if action == "load":
                if not cf.exists():
                    self.send_json(200, {"found": False, "data": {}}); return
                try:
                    data = json.loads(cf.read_text(encoding="utf-8"))
                    print("  [cache] load %s  entries=%d" % (cf.name, len(data)))
                    self.send_json(200, {"found": True, "data": data}, compress=True)
                except Exception as e:
                    self.send_json(500, {"error": str(e)})
            elif action == "save":
                data = payload.get("data", {})
                if not isinstance(data, dict):
                    self.send_json(400, {"error": "data must be an object"}); return
                try:
                    CACHE_DIR.mkdir(exist_ok=True)
                    text = json.dumps(data, separators=(",", ":"))
                    cf.write_text(text, encoding="utf-8")
                    kb = round(len(text)/1024)
                    print("  [cache] save %s  entries=%d  %d KB" % (cf.name, len(data), kb))
                    self.send_json(200, {"saved": True, "entries": len(data), "size_kb": kb})
                except Exception as e:
                    self.send_json(500, {"error": str(e)})
            elif action == "clear":
                try:
                    if cf.exists(): cf.unlink()
                    self.send_json(200, {"cleared": True})
                except Exception as e:
                    self.send_json(500, {"error": str(e)})
            else:
                self.send_json(400, {"error": "unknown action: " + action})
            return

        self.send_json(404, {"error": "unknown route"})


# -----------------------------------------------------------------------------
def launch_background(port):
    """Spawn itself as a silent background process (Windows .bat launcher)."""
    import sys
    here    = Path(__file__).parent.resolve()
    pidfile = here / ".genai-monitor.pid"
    logfile = here / "genai-monitor.log"

    # Prefer venv pythonw so no console window appears
    for candidate in [
        here / ".venv" / "Scripts" / "pythonw.exe",
        here / ".venv" / "Scripts" / "python.exe",
    ]:
        if candidate.exists():
            interpreter = str(candidate)
            break
    else:
        interpreter = sys.executable

    # Build STARTUPINFO to hide any console window unconditionally
    si = None
    try:
        si = subprocess.STARTUPINFO()
        si.dwFlags    |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 0  # SW_HIDE
    except AttributeError:
        si = None  # Not on Windows — STARTUPINFO not available

    p = subprocess.Popen(
        [interpreter, str(Path(__file__).resolve()),
         "--host", "127.0.0.1", "--port", str(port), "--no-browser"],
        cwd=str(here),
        creationflags=0x08000000 | 0x00000008,  # CREATE_NO_WINDOW | DETACHED_PROCESS
        startupinfo=si,
        stdout=open(str(logfile), "a"),
        stderr=subprocess.STDOUT,
    )
    pidfile.write_text(str(p.pid))
    print("Started PID %d on port %d" % (p.pid, port))


def main():
    import sys

    if hasattr(sys.stdout, "reconfigure"):
        try: sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception: pass
    if hasattr(sys.stderr, "reconfigure"):
        try: sys.stderr.reconfigure(encoding="utf-8", errors="replace")
        except Exception: pass

    parser = argparse.ArgumentParser(description="Viya4 GenAI Monitor")
    parser.add_argument("--host",       default="127.0.0.1",
                        help="Bind address. Default: 127.0.0.1 (local only). Use 0.0.0.0 for network access.")
    parser.add_argument("--port",       type=int, default=8899)
    parser.add_argument("--no-browser", action="store_true",
                        help="Do not open browser automatically")
    parser.add_argument("--server",      action="store_true",
                        help="Server mode: bind to 0.0.0.0 and skip browser open (same as --host 0.0.0.0 --no-browser)")
    parser.add_argument("--launch",     action="store_true",
                        help="Spawn as silent background process and exit")
    args = parser.parse_args()

    # --server is a shorthand for server/headless mode
    if args.server:
        args.host       = "0.0.0.0"
        args.no_browser = True

    if args.launch:
        launch_background(args.port)
        return

    import socket
    # Resolve the actual hostname so the printed URL is accessible from other machines
    try:
        hostname = socket.getfqdn()
        # Fall back to short hostname if FQDN is not meaningful
        if not hostname or hostname == 'localhost':
            hostname = socket.gethostname()
    except Exception:
        hostname = 'localhost'

    # Use localhost for loopback bind, actual hostname otherwise
    display_host = hostname if args.host not in ('127.0.0.1', 'localhost') else hostname
    url          = "http://%s:%d" % (display_host, args.port)
    url_local    = "http://localhost:%d" % args.port   # always works on this machine

    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)

    is_server_mode = args.host == "0.0.0.0" or args.server

    print("")
    print("+----------------------------------------------------------+")
    print("|          Viya4 GenAI Monitor                             |")
    print("+----------------------------------------------------------+")
    if is_server_mode:
        print("|  Network : %-49s|" % url)
        print("|  Local   : %-49s|" % url_local)
    else:
        print("|  Open    : %-49s|" % url_local)
    print("|  No external dependencies required.                     |")
    print("|  Ctrl+C to stop.                                        |")
    print("+----------------------------------------------------------+")
    print("")

    # Detect headless environment (Linux server without a display)
    import os as _os
    is_headless = (sys.platform != 'win32' and
                   not _os.environ.get('DISPLAY') and
                   not _os.environ.get('WAYLAND_DISPLAY'))

    if not args.no_browser and not is_headless:
        import threading as _t, webbrowser as _wb
        _t.Timer(1.2, lambda: _wb.open(url_local)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()

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
SUMMARY_DIR    = Path(__file__).parent / "summaries"
SUMMARY_CONFIG = Path(__file__).parent / "summary-config.json"

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


# =============================================================================
# Summary Engine
# =============================================================================

def _load_summary_config():
    """Load SMTP + recipient config from summary-config.json.
    Returns {} if file does not exist (email is optional)."""
    if not SUMMARY_CONFIG.exists():
        return {}
    try:
        return json.loads(SUMMARY_CONFIG.read_text(encoding="utf-8"))
    except Exception as e:
        print("  [summary] config read error: %s" % e)
        return {}


def _build_digest(period: str) -> dict:
    """Aggregate all cache files and compute usage statistics.

    Returns a dict with:
        period, generated_at, clusters, stats (per cluster+user),
        global_stats, plain_text (the formatted digest string).
    """
    import re
    from datetime import datetime, timezone, timedelta

    now      = datetime.now(timezone.utc)
    cutoff   = now - (timedelta(days=1) if period == "daily" else timedelta(days=7))
    cutoff_s = cutoff.isoformat()

    # Collect all cache files
    CACHE_DIR.mkdir(exist_ok=True)
    cache_files = list(CACHE_DIR.glob("*.json"))

    # We need: per-cluster aggregated stats
    # Cache filename pattern: cluster__user.json  (sanitised)
    clusters = {}   # { cluster_label: { users, chats, prompts, apps, hours, incomplete } }

    USER_TYPES   = {"userrequest", "userpromptrequest"}
    HIDDEN_TYPES = {"functionresult", "copilotfunctionresponse"}

    for cf in cache_files:
        # Reverse-engineer cluster+user from filename (best effort)
        stem  = cf.stem   # e.g. "viya4-lab-aks_viyacloud_sas_com__sasboot"
        parts = stem.split("__", 1)
        cluster_key = parts[0] if len(parts) == 2 else stem
        user_key    = parts[1] if len(parts) == 2 else "unknown"

        try:
            data = json.loads(cf.read_text(encoding="utf-8"))
        except Exception:
            continue

        if cluster_key not in clusters:
            clusters[cluster_key] = {
                "users":      set(),
                "chats":      0,
                "prompts":    0,
                "apps":       {},
                "hours":      [0]*24,
                "incomplete": 0,
                "canceled":   0,
            }
        c = clusters[cluster_key]

        for chat_id, entry in data.items():
            ts  = entry.get("modifiedTimeStamp") or entry.get("creationTimeStamp") or ""
            if ts < cutoff_s:
                continue   # outside the period window

            msgs = entry.get("msgs") or []
            # Application name — guess from first message context or skip
            app = entry.get("applicationName", "")

            c["chats"] += 1

            for m in msgs:
                mtype = (m.get("type") or "").lower()
                mts   = m.get("creationTimeStamp") or ""

                if mtype in HIDDEN_TYPES:
                    continue

                # Track incomplete / canceled
                if m.get("complete") is False:
                    c["incomplete"] += 1
                if m.get("canceled"):
                    c["canceled"] += 1

                if mtype not in USER_TYPES:
                    continue

                # Only count prompts within the window
                if mts and mts < cutoff_s:
                    continue

                c["prompts"] += 1

                # Created-by from chat-level field stored in msgs? Fall back to user_key
                creator = m.get("createdBy") or user_key
                c["users"].add(creator)

                # Hour-of-day breakdown (local UTC offset ignored — use UTC)
                if mts:
                    try:
                        hour = int(mts[11:13])
                        c["hours"][hour] += 1
                    except Exception:
                        pass

    # Convert sets to counts for serialisation
    for cl in clusters.values():
        cl["user_count"] = len(cl["users"])
        cl["users"]      = sorted(cl["users"])

    # ── Plain-text digest ─────────────────────────────────────────────────────
    period_label = "Last 24 Hours" if period == "daily" else "Last 7 Days"
    lines = []
    lines.append("=" * 58)
    lines.append("  Viya GenAI Monitor — %s Digest" % ("Daily" if period == "daily" else "Weekly"))
    lines.append("  Period : %s  (UTC)" % period_label)
    lines.append("  Generated : %s" % now.strftime("%Y-%m-%d %H:%M UTC"))
    lines.append("=" * 58)

    if not clusters:
        lines.append("")
        lines.append("  No cached data found.")
        lines.append("  Open the dashboard and fetch chats first.")
    else:
        for cl_name, c in sorted(clusters.items()):
            lines.append("")
            lines.append("  Cluster : %s" % cl_name.replace("_", "."))
            lines.append("  " + "-" * 54)
            lines.append("  Total chats    : %d" % c["chats"])
            lines.append("  Total prompts  : %d" % c["prompts"])
            lines.append("  Active users   : %d" % c["user_count"])

            if c["users"]:
                lines.append("")
                lines.append("  Users active:")
                for u in c["users"][:10]:
                    lines.append("    • %s" % u)
                if len(c["users"]) > 10:
                    lines.append("    … and %d more" % (len(c["users"]) - 10))

            # Peak hour
            peak_hour = c["hours"].index(max(c["hours"])) if any(c["hours"]) else None
            if peak_hour is not None and c["hours"][peak_hour] > 0:
                h = peak_hour
                ampm = "%d%s" % (h if h <= 12 else h-12, "am" if h < 12 else "pm")
                lines.append("")
                lines.append("  Peak hour      : %s UTC (%d prompts)" % (ampm, c["hours"][peak_hour]))

            if c["incomplete"] or c["canceled"]:
                lines.append("")
                lines.append("  ⚠  Attention:")
                if c["incomplete"]:
                    lines.append("    %d incomplete response(s) detected" % c["incomplete"])
                if c["canceled"]:
                    lines.append("    %d canceled response(s) detected" % c["canceled"])

    lines.append("")
    lines.append("=" * 58)
    lines.append("  Generated by Viya GenAI Monitor")
    lines.append("  https://github.com/sascommunities/technical-support-code")
    lines.append("=" * 58)

    return {
        "period":       period,
        "generated_at": now.isoformat(),
        "clusters":     clusters,
        "plain_text":   "\n".join(lines),
    }


def _save_digest(digest: dict) -> Path:
    """Write digest plain-text to summaries/ folder. Returns file path."""
    SUMMARY_DIR.mkdir(exist_ok=True)
    from datetime import datetime, timezone
    ts    = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
    fname = "summary-%s-%s.txt" % (digest["period"], ts)
    fpath = SUMMARY_DIR / fname
    fpath.write_text(digest["plain_text"], encoding="utf-8")
    print("  [summary] saved → %s" % fpath.name)
    return fpath


def _send_email(digest: dict, cfg: dict) -> dict:
    """Send digest via SMTP. Returns {sent, error}."""
    import smtplib
    import email.mime.text
    import email.mime.multipart
    from datetime import datetime, timezone

    smtp_host = cfg.get("smtp_host", "")
    smtp_port = int(cfg.get("smtp_port", 587))
    smtp_user = cfg.get("smtp_user", "")
    smtp_pass = cfg.get("smtp_pass", "")
    use_tls   = cfg.get("smtp_tls", True)
    from_addr = cfg.get("from", smtp_user)
    to_addrs  = cfg.get("to", [])

    if not smtp_host:
        return {"sent": False, "error": "smtp_host not configured"}
    if not to_addrs:
        return {"sent": False, "error": "no recipients configured"}

    period_label = "Daily" if digest["period"] == "daily" else "Weekly"
    subject = "Viya GenAI Monitor — %s Digest (%s UTC)" % (
        period_label,
        datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    )

    msg = email.mime.multipart.MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = from_addr
    msg["To"]      = ", ".join(to_addrs)
    msg.attach(email.mime.text.MIMEText(digest["plain_text"], "plain", "utf-8"))

    try:
        if use_tls:
            server = smtplib.SMTP(smtp_host, smtp_port, timeout=15)
            server.ehlo()
            server.starttls()
            server.ehlo()
        else:
            server = smtplib.SMTP(smtp_host, smtp_port, timeout=15)

        if smtp_user and smtp_pass:
            server.login(smtp_user, smtp_pass)

        server.sendmail(from_addr, to_addrs, msg.as_string())
        server.quit()
        print("  [summary] email sent to %s" % ", ".join(to_addrs))
        return {"sent": True, "recipients": to_addrs}

    except Exception as e:
        print("  [summary] email error: %s" % e)
        return {"sent": False, "error": str(e)}


# =============================================================================
# Threaded server: each request handled in its own thread
# =============================================================================
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
            elif action == "patch":
                # Incremental update: merge only changed/new entries into existing file
                delta = payload.get("data", {})
                if not isinstance(delta, dict):
                    self.send_json(400, {"error": "data must be an object"}); return
                try:
                    CACHE_DIR.mkdir(exist_ok=True)
                    # Load existing cache file (or start fresh)
                    existing = {}
                    if cf.exists():
                        try:
                            existing = json.loads(cf.read_text(encoding="utf-8"))
                        except Exception:
                            existing = {}
                    # Merge delta into existing
                    existing.update(delta)
                    text = json.dumps(existing, separators=(",", ":"))
                    cf.write_text(text, encoding="utf-8")
                    kb = round(len(json.dumps(delta, separators=(",",":"))) / 1024, 1)
                    print("  [cache] patch %s  patched=%d  total=%d  sent=%.1f KB" % (
                        cf.name, len(delta), len(existing), kb))
                    self.send_json(200, {
                        "saved":   True,
                        "patched": len(delta),
                        "total":   len(existing),
                        "size_kb": kb,
                    })
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

        # -- /api/summary: generate digest, save to file, optionally email -----
        if path == "/api/summary":
            period = payload.get("period", "daily")   # "daily" or "weekly"
            if period not in ("daily", "weekly"):
                self.send_json(400, {"error": "period must be 'daily' or 'weekly'"}); return

            try:
                digest   = _build_digest(period)
                saved    = _save_digest(digest)
                cfg_smtp = _load_summary_config()
                email_result = _send_email(digest, cfg_smtp) if cfg_smtp.get("smtp_host") else \
                               {"sent": False, "error": "no smtp_host in summary-config.json"}

                self.send_json(200, {
                    "ok":           True,
                    "period":       period,
                    "generated_at": digest["generated_at"],
                    "saved_to":     str(saved.name),
                    "email":        email_result,
                    "plain_text":   digest["plain_text"],
                    "clusters":     list(digest["clusters"].keys()),
                })
            except Exception as e:
                import traceback
                traceback.print_exc()
                self.send_json(500, {"error": str(e)})
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

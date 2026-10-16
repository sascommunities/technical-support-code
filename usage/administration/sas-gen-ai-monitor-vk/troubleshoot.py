#!/usr/bin/env python3
# A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
# DATE: 15OCT2026
#
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
troubleshoot.py -- Viya4 GenAI Monitor diagnostics

Checks the things that actually explain most support requests for this app:
  - is the Python runtime itself (and the stdlib modules this app needs,
    especially ssl) actually usable here?
  - are the project files present, syntactically valid, and writable where
    they need to be?
  - is the running server (if any) serving the SAME code that's on disk right
    now, or does it need a restart to pick up a recent edit?
  - does the local liveGenAiMonitoring.py / viya4_dashboard.html match what's
    on GitHub's main branch — and, ONLY with explicit confirmation, download
    and apply whichever one doesn't (current files backed up first)?
  - if this is a Docker deployment, is the container actually reachable under
    the Docker context/engine you're currently pointed at?

Not a substitute for tests/ (that's an internal regression suite for people
editing this project's code). This is for anyone running the app who hits a
problem and wants to know where to look before asking for help.

Usage:
  python3 troubleshoot.py                      # checks the local install on the default port
  python3 troubleshoot.py --port 9000
  python3 troubleshoot.py --url http://host:8899   # check a remote/Docker deployment
  python3 troubleshoot.py --no-server          # skip the running-server checks entirely
  python3 troubleshoot.py --no-github-check    # skip the GitHub comparison (e.g. air-gapped)
  python3 troubleshoot.py --yes                # auto-confirm a GitHub update instead of prompting
  python3 troubleshoot.py --log /tmp/diag.log  # write the support log somewhere specific
  python3 troubleshoot.py --no-log             # console output only, no log file

Every run also writes a support log (troubleshoot_<timestamp>.log in the
project folder by default): the full console output plus environment details,
the server's /health response, a directory listing and the tail of the server
log. Tokens, passwords and similar secrets are redacted before writing, so
the file can be attached to a support case as-is (it does still contain host
names, user names and chat IDs — review it first if that matters).

Normally invoked via troubleshoot.sh (Linux/macOS) or troubleshoot.bat (Windows),
which just locate a Python interpreter and hand off to this script — all the
actual checks live here so the two launchers can never drift apart.
"""

import argparse
import hashlib
import importlib
import json
import os
import platform
import re
import socket
import ssl
import subprocess
import sys
import tempfile
import traceback
import py_compile
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Canonical upstream — see check_github_latest(). Only these two files are
# ever offered for download: they're the only ones this script version-hashes
# at all, and keeping the set small keeps the (explicit, opt-in) overwrite
# step easy to reason about.
GITHUB_REPO_URL      = "https://github.com/sascommunities/technical-support-code/tree/main/usage/administration/sas-gen-ai-monitor-vk"
GITHUB_RAW_BASE      = "https://raw.githubusercontent.com/sascommunities/technical-support-code/main/usage/administration/sas-gen-ai-monitor-vk"
GITHUB_TRACKED_FILES = ("liveGenAiMonitoring.py", "viya4_dashboard.html")

_ok = _warn = _fail = 0

# Things collected along the way that only go into the support log's appendix
# (not the console): the raw /health response, whether a container was found.
_extra = {}

# Never let a credential end up in a file someone attaches to a support case.
# Nothing this script prints should contain one, but the appendix includes
# the server log and environment variables, so redact defensively.
_REDACT_PATTERNS = [
    (re.compile(r"eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*"), "<redacted-jwt>"),
    (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+"), r"\1<redacted>"),
    (re.compile(r"(?i)((?<![A-Za-z0-9_])(?:access_token|refresh_token|id_token|password|passwd|"
                r"client_secret|secret|code|verifier|token)\"?\s*[:=]\s*\"?)[^\"&\s,}]+"),
     r"\1<redacted>"),
    (re.compile(r"([A-Za-z][A-Za-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@"), r"\1<redacted>@"),
]


def redact(text: str) -> str:
    for pattern, repl in _REDACT_PATTERNS:
        text = pattern.sub(repl, text)
    return text


class _Tee:
    """Copies everything printed to the console into the support log (redacted)."""

    def __init__(self, stream, log_file):
        self.stream = stream
        self.log_file = log_file

    def write(self, s):
        self.stream.write(s)
        try:
            self.log_file.write(redact(s))
            self.log_file.flush()
        except Exception:
            pass
        return len(s)

    def flush(self):
        self.stream.flush()

    def __getattr__(self, name):
        return getattr(self.stream, name)


def _open_log(requested: str, project_dir: Path):
    """Opens the support log, falling back to the temp folder if the project
    folder isn't writable (itself a common reason people run this script)."""
    name = "troubleshoot_%s.log" % datetime.now().strftime("%Y%m%d_%H%M%S")
    candidates = [Path(requested)] if requested else [project_dir / name, Path(tempfile.gettempdir()) / name]
    for path in candidates:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            return path, open(path, "w", encoding="utf-8", errors="replace")
        except Exception:
            continue
    return None, None


def ok(msg):
    global _ok
    _ok += 1
    print("  [OK]   %s" % msg)


def warn(msg):
    global _warn
    _warn += 1
    print("  [WARN] %s" % msg)


def fail(msg):
    global _fail
    _fail += 1
    print("  [FAIL] %s" % msg)


def info(msg):
    print("  [--]   %s" % msg)


def section(title):
    print("")
    print(title)
    print("-" * len(title))


# Must compute the exact same way as _sha_short() in liveGenAiMonitoring.py —
# kept as a literal duplicate (not an import) so running this script never
# executes any of that file's own top-level code.
def _sha_short(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


# =============================================================================
def check_python_runtime():
    section("Python runtime")
    ver = sys.version_info
    info("Interpreter : %s" % sys.executable)
    info("Version     : %d.%d.%d" % (ver.major, ver.minor, ver.micro))
    if (ver.major, ver.minor) >= (3, 8):
        ok("Python %d.%d is new enough (3.8+ required)" % (ver.major, ver.minor))
    else:
        fail("Python %d.%d is too old — this app requires 3.8 or newer" % (ver.major, ver.minor))

    # Every stdlib module liveGenAiMonitoring.py actually imports. All of these
    # SHOULD always be present in a normal CPython install, which is exactly
    # why it's worth checking explicitly: a stripped-down/custom Python build
    # (common on locked-down corporate images) is the realistic way one of
    # these goes missing, and the failure otherwise only surfaces as a cryptic
    # traceback deep inside the server at the worst possible moment.
    required_modules = [
        "argparse", "base64", "gzip", "hashlib", "json", "re", "ssl",
        "subprocess", "threading", "time", "urllib.request", "urllib.parse",
        "urllib.error", "concurrent.futures", "http.server", "pathlib",
        "socketserver",
    ]
    missing = []
    for mod in required_modules:
        try:
            importlib.import_module(mod)
        except Exception as e:
            missing.append((mod, str(e)))
    if missing:
        for mod, err in missing:
            fail("Missing/broken stdlib module '%s': %s" % (mod, err))
    else:
        ok("All required stdlib modules import cleanly (%d checked)" % len(required_modules))

    # ssl gets its own check beyond just importing — this app talks to Viya
    # exclusively over HTTPS with certificate verification deliberately
    # disabled (self-signed Viya4 certs), via ssl._create_unverified_context().
    # A Python build with SSL support compiled out, or a FIPS-mode OpenSSL
    # that refuses this context style, breaks EVERY call to Viya while every
    # other check in this script still passes — worth isolating clearly.
    try:
        import ssl
        ssl._create_unverified_context()
        ok("ssl module supports the unverified context this app uses for self-signed Viya certs")
    except Exception as e:
        fail("ssl module cannot create the unverified context this app needs: %s" % e)


# =============================================================================
def check_project_files(project_dir: Path):
    section("Project files (%s)" % project_dir)
    server_path    = project_dir / "liveGenAiMonitoring.py"
    dashboard_path = project_dir / "viya4_dashboard.html"

    versions = {}
    for label, path in (("server", server_path), ("dashboard", dashboard_path)):
        if not path.exists():
            fail("Missing: %s" % path.name)
            continue
        data = path.read_bytes()
        versions[label] = _sha_short(data)
        ok("Found %s (%d KB, build %s)" % (path.name, round(len(data) / 1024), versions[label]))

    # Before 2026-10-16 the dashboard needed the browser's crypto.subtle to
    # sign in, which browsers only provide over HTTPS or on localhost — opened
    # as http://<server-ip>:8899, "Sign in with Viya" silently did nothing.
    if dashboard_path.exists():
        if b"_sha256(" in dashboard_path.read_bytes():
            ok("viya4_dashboard.html can sign in over plain HTTP (not only HTTPS/localhost)")
        else:
            warn("This viya4_dashboard.html build can only sign in over HTTPS or http://localhost. "
                 "Opened as http://<server-ip>:<port>, 'Sign in with Viya' does nothing. Update "
                 "the files, or use an SSH tunnel (ssh -L 8899:localhost:8899 <server>) and open "
                 "http://localhost:8899.")

    if server_path.exists():
        try:
            py_compile.compile(str(server_path), doraise=True, quiet=2)
            ok("liveGenAiMonitoring.py is syntactically valid Python")
        except py_compile.PyCompileError as e:
            fail("liveGenAiMonitoring.py fails to compile: %s" % e)

    # Optional JSON config files — if present, a hand-edited typo here fails
    # silently elsewhere (falls back to defaults) unless caught here.
    for cfg_name in ("pii-config.json", "summary-config.json"):
        cfg_path = project_dir / cfg_name
        if not cfg_path.exists():
            continue
        try:
            json.loads(cfg_path.read_text(encoding="utf-8"))
            ok("%s is valid JSON" % cfg_name)
        except Exception as e:
            fail("%s is not valid JSON — it will silently fall back to defaults: %s" % (cfg_name, e))

    return versions


# =============================================================================
def _fetch_github_file(filename: str) -> bytes:
    req = urllib.request.Request(GITHUB_RAW_BASE + "/" + filename,
                                  headers={"User-Agent": "gen-ai-monitor-troubleshoot"})
    with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=8) as r:
        return r.read()


def check_github_latest(project_dir: Path, auto_yes: bool):
    """Compares the tracked files against GitHub's main branch and, only with
    explicit confirmation, downloads and applies whichever ones differ.

    Note this can't tell WHICH side is newer — only that they differ. A
    mismatch just as often means "you have local changes not pushed there
    yet" as "an update is available." That ambiguity is exactly why this
    never applies anything without the explicit 'yes' (or --yes) below, and
    why it always backs up what it's about to overwrite first.
    """
    section("GitHub upstream (%s)" % GITHUB_REPO_URL)
    stale = {}
    try:
        for filename in GITHUB_TRACKED_FILES:
            local_path = project_dir / filename
            if not local_path.exists():
                continue
            local_bytes  = local_path.read_bytes()
            remote_bytes = _fetch_github_file(filename)
            if local_bytes == remote_bytes:
                ok("%s matches GitHub's main branch" % filename)
            else:
                warn("%s differs from GitHub's main branch (local build %s, upstream build %s)"
                     % (filename, _sha_short(local_bytes), _sha_short(remote_bytes)))
                stale[filename] = (local_path, local_bytes, remote_bytes)
    except Exception as e:
        info("Could not reach GitHub to compare versions (%s) — skipping. Not treated as a "
             "failure: no internet access, or a proxy/firewall blocking it, is normal here." % e)
        return

    if not stale:
        return

    print("")
    print("  %d file(s) differ from GitHub's main branch: %s" % (len(stale), ", ".join(stale)))
    print("  Repo: %s" % GITHUB_REPO_URL)

    proceed = auto_yes
    if not proceed:
        if not sys.stdin.isatty():
            info("Not an interactive session — skipping the update prompt. Re-run interactively, "
                 "or pass --yes, to apply it.")
            return
        print("")
        answer = input("  Download and apply the GitHub version of the file(s) above? Your "
                        "current files are backed up first. Type 'yes' to confirm, anything "
                        "else to skip: ").strip().lower()
        proceed = answer == "yes"
        info("Answer: %s" % (answer or "(empty)"))

    if not proceed:
        info("Skipped — no files were changed.")
        return

    backup_dir = project_dir / ("backup_%s" % datetime.now().strftime("%Y%m%d_%H%M%S"))
    backup_dir.mkdir(exist_ok=True)
    for filename, (local_path, local_bytes, remote_bytes) in stale.items():
        (backup_dir / filename).write_bytes(local_bytes)
        local_path.write_bytes(remote_bytes)
        ok("Updated %s" % filename)
    warn("Previous version(s) backed up to %s — restart the server (and hard-reload any open "
         "browser tab) to apply the update." % backup_dir)


# =============================================================================
def check_disk_permissions(project_dir: Path):
    section("Disk permissions")
    for sub in ("cache", "summaries"):
        d = project_dir / sub
        try:
            d.mkdir(exist_ok=True)
            probe = d / ".troubleshoot-write-test"
            probe.write_text("ok", encoding="utf-8")
            probe.unlink()
            ok("%s/ is writable" % sub)
        except Exception as e:
            fail("%s/ is not writable — chat history and digests can't be saved: %s" % (sub, e))


# =============================================================================
def check_port(host: str, port: int) -> bool:
    """Returns True if *something* is listening on host:port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.5)
        return s.connect_ex((host, port)) == 0


def check_running_server(url: str, file_versions: dict) -> bool:
    """Returns True only if the server actually answered /health."""
    section("Running server (%s)" % url)
    try:
        with urllib.request.urlopen(url + "/health", timeout=5) as r:
            data = json.loads(r.read())
    except urllib.error.URLError:
        host_port = url.split("://", 1)[-1]
        host, _, port_s = host_port.partition(":")
        port = int(port_s or 80)
        if check_port(host or "127.0.0.1", port):
            fail("Something is listening on %s but it didn't answer /health like this app's "
                 "server does — likely a different process holding that port." % host_port)
        else:
            warn("Nothing answered at %s — server is not running (or not reachable from here). "
                 "Skipping the rest of the running-server checks." % url)
        return False
    except Exception as e:
        fail("Unexpected error reaching %s/health: %s" % (url, e))
        return False

    ok("Server is up")
    _extra["health"] = data

    if "server_restart_needed" not in data:
        warn("The running server predates this diagnostics endpoint (older build, before "
             "2026-10-15) — restart it to get version/health reporting at all.")
        return True

    info("Started: %s" % data.get("started_at", "?"))
    if data.get("server_restart_needed"):
        warn("liveGenAiMonitoring.py on disk has changed since this server process started "
             "(running build %s, on-disk build %s) — restart the server to apply the update."
             % (data.get("server_code_version"), data.get("server_code_on_disk")))
    else:
        ok("Running server matches liveGenAiMonitoring.py on disk (build %s) — no restart needed"
           % data.get("server_code_version"))

    local_dash = file_versions.get("dashboard")
    server_dash = data.get("dashboard_version")
    if local_dash and server_dash:
        if local_dash == server_dash:
            ok("Server is serving the same viya4_dashboard.html that's in this folder (build %s)" % server_dash)
        else:
            warn("Server is serving a DIFFERENT viya4_dashboard.html (build %s) than the one in "
                 "this folder (build %s) — probably running from another directory/copy. Any "
                 "open browser tab older than the server's current build will show a "
                 "'reload to get the latest' notice automatically." % (server_dash, local_dash))

    return True


# =============================================================================
def check_docker(url_reachable: bool):
    section("Docker (best-effort — skipped if Docker isn't involved)")
    docker = None
    for candidate in ("docker",):
        try:
            subprocess.run([candidate, "--version"], capture_output=True, timeout=5, check=True)
            docker = candidate
            break
        except Exception:
            continue
    if not docker:
        info("Docker CLI not found on PATH — skipping (fine if you're not running this in Docker)")
        return

    try:
        r = subprocess.run([docker, "info"], capture_output=True, timeout=10, text=True)
        daemon_up = r.returncode == 0
    except Exception:
        daemon_up = False

    if not daemon_up:
        warn("`docker info` failed on the current context — the Docker daemon isn't reachable here")
    else:
        ok("Docker daemon is reachable on the current context")

    try:
        r = subprocess.run([docker, "ps", "--filter", "name=gen-ai-monitor", "--format", "{{.Names}}\t{{.Status}}"],
                            capture_output=True, timeout=10, text=True)
        running = [l for l in r.stdout.splitlines() if l.strip()]
    except Exception:
        running = []

    _extra["containers"] = [l.split("\t", 1)[0] for l in running]
    if running:
        for line in running:
            ok("Container found: %s" % line)
    elif url_reachable:
        # The server answered /health, but no matching container shows up on
        # THIS context — the classic multiple-Docker-engines trap (e.g. a
        # container actually running under Rancher Desktop's engine while the
        # default `docker` CLI context points at a different one). Worth
        # calling out explicitly since it's confusing and easy to chase the
        # wrong engine for an hour.
        warn("The server answered a health check, but no 'gen-ai-monitor' container shows up "
             "under the current Docker context. If you have more than one Docker engine "
             "installed (e.g. Docker Desktop AND Rancher Desktop), it's probably running under "
             "a different one. Try: `docker context ls`, then `docker --context <name> ps`.")
    else:
        info("No 'gen-ai-monitor' container found on the current context (and no server answered either)")

    try:
        r = subprocess.run([docker, "context", "ls", "--format", "{{.Name}}"],
                            capture_output=True, timeout=5, text=True)
        contexts = [l.strip() for l in r.stdout.splitlines() if l.strip()]
        if len(contexts) > 1:
            info("Available Docker contexts: %s" % ", ".join(contexts))
    except Exception:
        pass


# =============================================================================
def _tail(path: Path, lines: int) -> list:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.readlines()[-lines:]


def write_support_appendix(log_file, project_dir: Path, args):
    """Extra detail for whoever reads the log later — written to the file only,
    so the console stays as short as it always was."""
    def w(line=""):
        log_file.write(redact(line) + "\n")

    def head(title):
        w(); w(title); w("-" * len(title))

    head("Environment")
    w("  Generated   : %s" % datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z"))
    w("  Host        : %s" % socket.gethostname())
    w("  OS          : %s" % platform.platform())
    w("  Machine     : %s" % platform.machine())
    w("  Python      : %s (%s)" % (sys.version.split()[0], sys.executable))
    w("  OpenSSL     : %s" % ssl.OPENSSL_VERSION)
    w("  Working dir : %s" % os.getcwd())
    w("  Arguments   : %s" % (" ".join(sys.argv[1:]) or "(none)"))
    for var in sorted(os.environ):
        if var.upper() in ("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY",
                           "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE") \
                or var.upper().startswith("GENAI_MONITOR"):
            w("  env %-20s= %s" % (var, os.environ[var]))

    if "health" in _extra:
        head("Server /health response")
        for line in json.dumps(_extra["health"], indent=2, sort_keys=True).splitlines():
            w("  " + line)

    head("Project directory listing (%s)" % project_dir)
    try:
        for entry in sorted(project_dir.iterdir(), key=lambda e: e.name.lower()):
            st = entry.stat()
            stamp = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
            if entry.is_dir():
                # Folder contents (chat caches, backups, the venv) aren't useful
                # here and some are private — just say how big they are.
                try:
                    count = sum(1 for _ in entry.iterdir())
                except Exception:
                    count = "?"
                w("  %s  %10s  %s/  (%s entries)" % (stamp, "<dir>", entry.name, count))
            else:
                w("  %s  %10d  %s" % (stamp, st.st_size, entry.name))
    except Exception as e:
        w("  Could not list directory: %s" % e)

    server_log = project_dir / "genai-monitor.log"
    head("Server log — last %d lines (%s)" % (args.log_lines, server_log))
    if server_log.exists():
        try:
            for line in _tail(server_log, args.log_lines):
                w("  " + line.rstrip("\n"))
        except Exception as e:
            w("  Could not read: %s" % e)
    else:
        w("  Not found (normal for a Docker deployment, or if the server was never started "
          "with gen-ai-monitor.sh / gen-ai-monitor-start.bat).")

    for name in _extra.get("containers", []):
        head("Docker container log — last %d lines (%s)" % (args.log_lines, name))
        try:
            r = subprocess.run(["docker", "logs", "--tail", str(args.log_lines), name],
                               capture_output=True, timeout=15, text=True, errors="replace")
            for line in (r.stdout + r.stderr).splitlines():
                w("  " + line)
        except Exception as e:
            w("  Could not read: %s" % e)


# =============================================================================
def main():
    parser = argparse.ArgumentParser(description="Viya4 GenAI Monitor diagnostics")
    parser.add_argument("--dir",  default=str(HERE), help="Project directory (default: this script's own folder)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8899)
    parser.add_argument("--url",  default=None, help="Full base URL, overrides --host/--port (e.g. for a remote/Docker deployment)")
    parser.add_argument("--no-server", action="store_true", help="Skip checks against a running server")
    parser.add_argument("--no-docker", action="store_true", help="Skip Docker checks")
    parser.add_argument("--no-github-check", action="store_true",
                         help="Skip comparing against GitHub's main branch (e.g. on an air-gapped network)")
    parser.add_argument("--yes", action="store_true",
                         help="Auto-confirm downloading an updated file from GitHub without prompting "
                              "(only matters together with a GitHub mismatch; still backs up first)")
    parser.add_argument("--log", default=None,
                         help="Where to write the support log (default: troubleshoot_<timestamp>.log "
                              "in the project folder)")
    parser.add_argument("--no-log", action="store_true", help="Don't write a support log file")
    parser.add_argument("--log-lines", type=int, default=200,
                         help="How many lines of the server/container log to include (default: 200)")
    args = parser.parse_args()

    project_dir = Path(args.dir).resolve()
    url = args.url.rstrip("/") if args.url else "http://%s:%d" % (args.host, args.port)

    log_path = log_file = None
    if not args.no_log:
        log_path, log_file = _open_log(args.log, project_dir)
        if log_file:
            sys.stdout = _Tee(sys.stdout, log_file)

    try:
        run_checks(args, project_dir, url)
    except SystemExit:
        raise
    except BaseException:
        # Get the crash itself into the support log too — that's exactly when
        # someone needs to send it.
        if log_file:
            log_file.write("\n" + redact(traceback.format_exc()))
        raise
    finally:
        if log_file:
            try:
                write_support_appendix(log_file, project_dir, args)
            except Exception as e:
                log_file.write("\nCould not write support appendix: %s\n" % e)
            sys.stdout = sys.stdout.stream
            log_file.close()
            print("  Support log written to: %s" % log_path)
            print("  Attach this file when asking for help (secrets are redacted; it still")
            print("  contains host names, user names and chat IDs — review it if that matters).")
            print("")
        elif not args.no_log:
            print("  Could not write a support log file (no writable location found).")
            print("")

    sys.exit(1 if _fail else 0)


def run_checks(args, project_dir: Path, url: str):

    print("")
    print("  Viya4 GenAI Monitor — Diagnostics")
    print("  ==================================")

    check_python_runtime()
    file_versions = check_project_files(project_dir)
    if not args.no_github_check:
        check_github_latest(project_dir, args.yes)
    check_disk_permissions(project_dir)

    url_reachable = False
    if not args.no_server:
        url_reachable = check_running_server(url, file_versions)

    if not args.no_docker:
        check_docker(url_reachable)

    print("")
    print("  Summary: %d OK, %d warning(s), %d failure(s)" % (_ok, _warn, _fail))
    print("")


if __name__ == "__main__":
    main()

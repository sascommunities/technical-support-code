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
import hashlib
import ipaddress
import json
import os
import posixpath
import re
import socket
import ssl
import subprocess
import threading
import time
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
PII_CONFIG     = Path(__file__).parent / "pii-config.json"


# -- Troubleshooting: content-hash "version" fingerprints -------------------
# No build step and no release numbers here — a short hash of a file's own
# bytes is the simplest fingerprint that is always exactly right and needs no
# manual bumping. SERVER_CODE_VERSION is fixed at process start (what this
# running process is actually executing); /health also reports a fresh
# on-disk hash so a stale, forgotten-to-restart process is easy to spot.
def _sha_short(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]

SERVER_STARTED_AT   = time.time()
SERVER_CODE_VERSION = _sha_short(Path(__file__).read_bytes())


# -- Cache filename helper ----------------------------------------------------
def _cache_filename(cluster: str, user: str) -> Path:
    safe = re.sub(r"[^a-z0-9._-]", "_", (cluster + "__" + user).lower())
    return CACHE_DIR / (safe + ".json")


# =============================================================================
# Guard-rails: server-side admin check + function-call redaction / PII scan
#
# copilotFunctionResponse / functionResult messages carry the raw arguments
# and results of every Copilot tool call (which tables/datasources were
# touched, what was returned). This is exactly the data a non-admin viewer
# must never receive — so it is checked and stripped here, server-side,
# before it ever reaches the browser. Doing it client-side (as the earlier
# Graphs-tab admin gate does) only hides the DOM; the raw JSON would still
# have been sent to every viewer's browser.
# =============================================================================

_CHAT_MESSAGES_RE = re.compile(r"/genAiGateway/v1/chats/[^/]+/messages", re.I)
_CHAT_LIST_RE     = re.compile(r"^/genAiGateway/v1/chats(?:\?|$)", re.I)
_FUNCTION_MSG_TYPES = {"functionresult", "copilotfunctionresponse"}

# -- Per-user chat visibility: non-admins may only see their own chats -------
# Regular users are not entitled to browse everyone else's Copilot activity —
# only SAS Administrators get the cross-user "monitor the whole environment"
# view. Enforced here (server-side, on the already-fetched Viya data) so a
# non-admin can never see another user's chats no matter what the client sends.
def _filter_own_chats(items: list, is_admin: bool, requester: str) -> list:
    if is_admin or not isinstance(items, list):
        return items
    req_l = (requester or "").lower()
    return [c for c in items if isinstance(c, dict) and (c.get("createdBy") or "").lower() == req_l]


def _filter_own_cache(data: dict, is_admin: bool, requester: str) -> dict:
    """Same rule as _filter_own_chats, applied to the persisted-cache dict shape
    ({chatId: {..., createdBy, msgs, ...}}) instead of a plain list."""
    if is_admin or not isinstance(data, dict):
        return data
    req_l = (requester or "").lower()
    return {cid: e for cid, e in data.items()
            if isinstance(e, dict) and (e.get("createdBy") or "").lower() == req_l}


def _chat_owner(viya_url: str, bearer: str, chat_id: str):
    """Look up a single chat's createdBy directly from Viya — used as a defense-
    in-depth check before returning ANY chat's messages to a non-admin, so
    pasting a foreign chat ID into the Chat ID filter can't be used to bypass
    the list-level filtering above. Returns None (fail-closed) on any error."""
    try:
        req = urllib.request.Request(
            "%s/genAiGateway/v1/chats/%s" % (viya_url, chat_id),
            headers={"Authorization": "Bearer %s" % bearer, "Accept": "application/vnd.sas.collection+json"},
            method="GET",
        )
        with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as r:
            return json.loads(r.read()).get("createdBy")
    except Exception as e:
        print("  [chat-owner] error for %s: %s" % (chat_id, e))
        return None


def _username_from_token(token: str):
    """Extract the authenticated username directly from the bearer token (a
    standard UAA-issued JWT, per SAS Viya's SASLogon) instead of trusting
    whatever "user" string the client sends in the request body — that field
    is just JSON the browser wrote and can be edited in devtools to claim ANY
    identity (e.g. "sasboot") without actually holding that identity's token.
    The real Viya API calls this proxy makes on the caller's behalf still
    require a genuinely valid token for whoever is embedded in it, so that's
    what every local admin/ownership decision must be based on.
    Returns None (fail-closed) if the token isn't a decodable JWT."""
    try:
        parts = (token or "").split(".")
        if len(parts) != 3:
            return None
        payload_b64 = parts[1]
        padding = "=" * (-len(payload_b64) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload_b64 + padding))
        return claims.get("user_name") or claims.get("sub") or None
    except Exception:
        return None


# -- Viya URL policy ----------------------------------------------------------
# Every route that takes a "url" makes this server fetch it, so an unchecked
# value turns the proxy into a tool for reaching things only this machine can
# reach. Always enforced: http/https only (urllib would otherwise happily open
# file:// and ftp:// URLs) and never a link-local address (cloud instance
# metadata endpoints live there; no Viya ever does). Optional, for shared
# deployments: GENAI_MONITOR_ALLOWED_HOSTS="viya.example.com,*.corp.example.com"
# pins which Viya environments may be used at all. Unset (the default) keeps
# today's behavior — any environment can be chosen when creating a profile.
_ALLOWED_HOSTS = [h.strip().lower() for h in os.environ.get("GENAI_MONITOR_ALLOWED_HOSTS", "").split(",") if h.strip()]

def _url_allowed(viya_url: str) -> bool:
    try:
        parsed = urllib.parse.urlsplit(viya_url)
    except Exception:
        return False
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in ("http", "https") or not host:
        return False
    if _ALLOWED_HOSTS and not any(
            host == h or (h.startswith("*.") and host.endswith(h[1:])) for h in _ALLOWED_HOSTS):
        return False
    try:
        for info in socket.getaddrinfo(host, None):
            if ipaddress.ip_address(info[4][0].split("%")[0]).is_link_local:
                return False
    except socket.gaierror:
        pass  # unresolvable — the real request will simply fail
    return True


# -- Verified identity --------------------------------------------------------
# _username_from_token() only DECODES the JWT — it can't check the signature,
# so on its own anyone can hand-craft a token claiming to be "sasboot" or any
# other user. That's harmless where the same request then fetches data from
# Viya with that token (Viya rejects a forged one), but not on routes that
# never touch Viya with it (/api/cache, /api/pii-words, /api/is-admin). Those
# use this instead: Viya itself must accept the token and confirm, via
# /identities/users/@currentUser, that it belongs to the user it claims.
# Positive results are cached briefly per token so this costs one extra Viya
# call per session, not per request.
_VERIFY_CACHE = {}
_VERIFY_LOCK  = threading.Lock()
_VERIFY_TTL   = 300  # seconds

def _verified_username(viya_url: str, token: str):
    claimed = _username_from_token(token)
    if not claimed or not viya_url or not _url_allowed(viya_url):
        return None
    key = (viya_url, hashlib.sha256(token.encode()).hexdigest())
    now = time.time()
    with _VERIFY_LOCK:
        hit = _VERIFY_CACHE.get(key)
        if hit and (now - hit[1]) < _VERIFY_TTL:
            return hit[0]
    try:
        req = urllib.request.Request(
            "%s/identities/users/@currentUser" % viya_url,
            headers={"Authorization": "Bearer %s" % token, "Accept": "application/json"},
            method="GET",
        )
        with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as r:
            actual = (json.loads(r.read()).get("id") or "")
    except Exception as e:
        print("  [identity] token rejected/unverifiable for claimed user %s: %s" % (claimed, e))
        return None
    if actual.lower() != claimed.lower():
        print("  [identity] token claims %s but Viya says %s — rejected" % (claimed, actual))
        return None
    with _VERIFY_LOCK:
        for k in [k for k, v in _VERIFY_CACHE.items() if (now - v[1]) >= _VERIFY_TTL]:
            del _VERIFY_CACHE[k]
        _VERIFY_CACHE[key] = (claimed, now)
    return claimed


def _cluster_from_url(viya_url: str) -> str:
    """Cache-file namespace, derived from the (verified) Viya URL itself rather
    than a separate client-supplied field — otherwise a token vouched for by
    one server could be used to open another environment's cache files. Same
    normalization the dashboard has always used, so existing files still match."""
    c = viya_url.lower()
    for prefix in ("https://", "http://"):
        if c.startswith(prefix):
            c = c[len(prefix):]
    return c.rstrip("/")


# -- API path normalization (/api/proxy-all) ---------------------------------
# The chat-visibility guard-rails match on the path, so the path that's
# checked must be exactly the path that's fetched. Without this, variants the
# regexes don't recognize but Viya's ingress resolves to the same endpoint
# (percent-encoding, "//", "/x/../", a trailing "/", ";params") would skip
# the filtering/redaction entirely.
def _normalize_api_path(api_path: str):
    path, sep, query = api_path.partition("?")
    path = urllib.parse.unquote(path)
    if ";" in path or "\\" in path:
        return None
    path = "/" + posixpath.normpath("/" + path).lstrip("/")
    return urllib.parse.quote(path, safe="/:@-._~!$&'()*+,=") + (sep + query if sep else "")


# What a non-admin's dashboard ever requests through /api/proxy-all — the
# chat list and one chat's messages. Anything else under the GenAI Gateway is
# admin-only through this proxy.
_NON_ADMIN_PATH_RE = re.compile(r"^/genAiGateway/v1/chats(?:/[^/?]+/messages)?(?:\?|$)", re.I)


# Chat metadata the dashboard shows as labels (app name, Copilot agent id and
# version). These come from whatever client created the chat via the GenAI
# Gateway API, so a crafted value could otherwise carry HTML into an admin's
# dashboard. Legitimate values never contain these characters.
_META_STRIP_RE = re.compile(r"[<>\"'`]")

def _neutralize_chat_meta(items):
    if not isinstance(items, list):
        return
    for c in items:
        if not isinstance(c, dict):
            continue
        if isinstance(c.get("applicationName"), str):
            c["applicationName"] = _META_STRIP_RE.sub("", c["applicationName"])
        cp = c.get("copilot")
        if isinstance(cp, dict):
            for k in ("id", "version"):
                if isinstance(cp.get(k), str):
                    cp[k] = _META_STRIP_RE.sub("", cp[k])

# search_capability_registry only returns tool/skill documentation (schemas,
# generic descriptions) — never real user/query data — so scanning it for PII
# words just produces false positives on doc text (e.g. "address" showing up
# in a search-syntax example). Excluded from the PII scan; the raw payload is
# still shown to admins, just never flagged.
_PII_SCAN_EXCLUDED_FUNCTIONS = {"search_capability_registry"}

# Fields that are pure repeated boilerplate (full tool schemas, skill prompts,
# report snapshots) on every function-related message — never useful for
# audit/PII purposes, just cache/bandwidth bloat. Stripped for every viewer.
_NOISE_KEYS = ("reservedTools", "systemSkills", "chatReport", "report")

# -- Admin check ---------------------------------------------------------------
# Admin view = sasboot, or a SASAdministrators member who ASSUMED that group
# for this session. SASAdministrators is an assumable group: at sign-in SAS
# Logon asks whether to opt in, and only on "yes" does Viya put the group in
# the access token's scopes. Membership alone isn't enough — a member who
# declined is a regular user for that session, here exactly as in Viya.
#
# The token's claims are only trusted once Viya has accepted that exact token:
# every caller either verified it first (_verified_username) or has already
# fetched data from Viya with it (/api/proxy-all), so a hand-made token
# claiming the scope gets nowhere.
_ADMIN_GROUP = "sasadministrators"

def _token_claims(token: str) -> dict:
    try:
        payload_b64 = (token or "").split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload_b64 + "=" * (-len(payload_b64) % 4)))
        return claims if isinstance(claims, dict) else {}
    except Exception:
        return {}


def _token_assumed_admin(token: str) -> bool:
    claims = _token_claims(token)
    granted = []
    for key in ("scope", "authorities"):
        v = claims.get(key)
        granted += v.split() if isinstance(v, str) else (v if isinstance(v, list) else [])
    return any(isinstance(g, str) and g.lower() == _ADMIN_GROUP for g in granted)


def _is_admin(viya_url: str, token: str, user: str) -> bool:
    if (user or "").lower() == "sasboot":
        return True
    if not token or not viya_url:
        return False
    return _token_assumed_admin(token)


# -- Membership lookup (hint only) --------------------------------------------
# Never grants anything. Used solely so /api/is-admin can tell a member who
# declined to assume SASAdministrators at sign-in why they're seeing the
# regular-user view, and how to get the admin one.
_ADMIN_CACHE      = {}
_ADMIN_CACHE_LOCK = threading.Lock()
_ADMIN_CACHE_TTL  = 60  # seconds

def _is_admin_group_member(viya_url: str, token: str, user: str) -> bool:
    user_l = (user or "").lower()
    if not token or not viya_url:
        return False

    cache_key = (viya_url, user_l)
    now = time.time()
    with _ADMIN_CACHE_LOCK:
        cached = _ADMIN_CACHE.get(cache_key)
        if cached is not None and (now - cached[1]) < _ADMIN_CACHE_TTL:
            return cached[0]

    is_member = False
    try:
        req = urllib.request.Request(
            "%s/identities/groups/SASAdministrators/userMembers?limit=1000" % viya_url,
            headers={
                "Authorization": "Bearer %s" % token,
                "Accept":        "application/vnd.sas.collection+json",
            },
            method="GET",
        )
        with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as r:
            data = json.loads(r.read())
        is_member = any((item.get("id") or "").lower() == user_l for item in data.get("items", []))
    except Exception as e:
        print("  [admin-member-hint] lookup failed for %s: %s" % (user_l, e))

    with _ADMIN_CACHE_LOCK:
        _ADMIN_CACHE[cache_key] = (is_member, now)
    return is_member


# -- Admin-managed custom PII word list ("PII's" panel in the header) --------
# Lets admins define what counts as sensitive instead of us guessing regexes.
# Stored as {"words": [...]} and merged into _pii_flags() below.
_pii_words_cache = {"words": [], "mtime": 0.0}
_pii_words_lock  = threading.Lock()

def _parse_pii_words(text: str) -> list:
    """Parse the "word1, word2, 'multi word'" format the PII's panel uses.
    A single wrapping pair of double quotes around the whole value is optional."""
    text = (text or "").strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    words = []
    for token in text.split(","):
        token = token.strip()
        if not token:
            continue
        if len(token) >= 2 and token[0] == "'" and token[-1] == "'":
            token = token[1:-1].strip()
        if token:
            words.append(token)
    return words


def _format_pii_words(words: list) -> str:
    if not words:
        return ""
    parts = ["'%s'" % w if " " in w else w for w in words]
    return '"' + ", ".join(parts) + '"'


def _load_pii_words() -> list:
    if not PII_CONFIG.exists():
        return []
    try:
        mtime = PII_CONFIG.stat().st_mtime
    except Exception:
        return []
    with _pii_words_lock:
        if _pii_words_cache["mtime"] != mtime:
            try:
                data  = json.loads(PII_CONFIG.read_text(encoding="utf-8"))
                words = [w for w in data.get("words", []) if isinstance(w, str) and w]
            except Exception:
                words = []
            _pii_words_cache["words"] = words
            _pii_words_cache["mtime"] = mtime
        return list(_pii_words_cache["words"])


def _pii_flags(obj) -> list:
    """Scan a JSON-serialisable object for admin-defined words from the PII's
    panel — the only source of PII flags; nothing here is guessed/built-in.
    Returns a sorted list of matched words, or [] if nothing found."""
    try:
        blob = json.dumps(obj, ensure_ascii=False, default=str)
    except Exception:
        blob = str(obj)
    lower = blob.lower()
    flags = set()
    for w in _load_pii_words():
        if w.lower() in lower:
            flags.add(w)
    return sorted(flags)


def _strip_noise(msg: dict):
    """Remove known boilerplate fields from a message's context/data/
    functionCall.arguments in place. Applied regardless of admin status."""
    if not isinstance(msg, dict):
        return
    for key in _NOISE_KEYS:
        msg.pop(key, None)
    for sub_key in ("context", "data"):
        sub = msg.get(sub_key)
        if isinstance(sub, dict):
            for key in _NOISE_KEYS:
                sub.pop(key, None)
    fc = msg.get("functionCall")
    if isinstance(fc, dict):
        args = fc.get("arguments")
        if isinstance(args, dict):
            args.pop("embedding", None)


def _scrub_chat_messages(messages: list, is_admin: bool) -> list:
    """Strip boilerplate from every message. For function-call/result
    messages: admins keep the real payload (annotated with piiFlags, except
    for _PII_SCAN_EXCLUDED_FUNCTIONS); non-admins get a redacted placeholder
    so the raw data never leaves the server for them."""
    if not isinstance(messages, list):
        return messages

    # functionResult messages don't carry the function name themselves —
    # only the copilotFunctionResponse call does. Build id -> name so a
    # result can be traced back to the call that produced it.
    call_names = {}
    for m in messages:
        if isinstance(m, dict) and (m.get("type") or "").lower() == "copilotfunctionresponse":
            fc = m.get("functionCall")
            if isinstance(fc, dict) and m.get("id"):
                call_names[m["id"]] = fc.get("name")

    for m in messages:
        if not isinstance(m, dict):
            continue
        _strip_noise(m)
        mtype = (m.get("type") or "").lower()
        if mtype not in _FUNCTION_MSG_TYPES:
            continue
        if is_admin:
            fn_name = (m.get("functionCall") or {}).get("name") if mtype == "copilotfunctionresponse" \
                      else call_names.get(m.get("copilotFunctionResponseId"))
            if fn_name not in _PII_SCAN_EXCLUDED_FUNCTIONS:
                flags = _pii_flags(m.get("functionCall") or m.get("data"))
                if flags:
                    m["piiFlags"] = flags
        else:
            if "functionCall" in m:
                m["functionCall"] = {"redacted": True}
            if "data" in m:
                m["data"] = {"redacted": True}
    return messages

# -- Dashboard cache: read once from disk, serve many times --------------------
# Every served copy carries its own content hash as window.__VIYA4_BUILD__ (a
# tiny inline <script> spliced right after <head>) so an already-open tab can
# notice later, via /health, that the file on disk has since changed — see
# _checkBuildFreshness() in viya4_dashboard.html.
_dash_cache = {"data": None, "mtime": 0.0, "version": None}
_dash_lock  = threading.Lock()

def get_dashboard():
    if not DASHBOARD_HTML.exists():
        return b"<h1>viya4_dashboard.html not found</h1>"
    mtime = DASHBOARD_HTML.stat().st_mtime
    with _dash_lock:
        if _dash_cache["mtime"] != mtime:
            raw     = DASHBOARD_HTML.read_bytes()
            version = _sha_short(raw)
            marker  = ('<script id="viya4-build">window.__VIYA4_BUILD__=%s;</script>'
                       % json.dumps(version)).encode()
            data    = raw.replace(b"<head>", b"<head>" + marker, 1) if b"<head>" in raw \
                      else marker + raw
            _dash_cache["data"]    = data
            _dash_cache["mtime"]   = mtime
            _dash_cache["version"] = version
    return _dash_cache["data"]


def get_dashboard_version() -> str:
    get_dashboard()  # ensures the cache (and its version) is fresh
    return _dash_cache["version"] or ""


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
        # API responses can carry access/refresh tokens (/api/token) and chat
        # data — never let a browser or intermediate proxy store them.
        self.send_header("Cache-Control",  "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, code, html):
        self.send_response(code)
        self.send_header("Content-Type",   "text/html; charset=utf-8")
        self.send_header("Content-Length", len(html))
        self.send_header("Cache-Control",  "no-cache")
        self.end_headers()
        self.wfile.write(html)

    def end_headers(self):
        # Baseline browser hardening on every response: no MIME sniffing, no
        # framing by other sites (clickjacking), no Referer leaking the
        # dashboard's address to links opened from chat content.
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options",        "DENY")
        self.send_header("Referrer-Policy",        "no-referrer")
        super().end_headers()

    # Generous (largest real cache file today is ~7 MB) — only here so one
    # request can't make the server buffer an arbitrarily large body.
    _MAX_BODY = 256 * 1024 * 1024

    def read_json(self):
        n = int(self.headers.get("Content-Length", 0))
        if n > self._MAX_BODY:
            raise ValueError("request body too large")
        return json.loads(self.rfile.read(n)) if n else {}

    # -- Routes ----------------------------------------------------------------
    # The dashboard only ever calls this server from its own origin, so there
    # is nothing to approve cross-origin: no Access-Control-Allow-* headers.
    # Together with requiring a JSON Content-Type on every POST (which a
    # browser can't send cross-origin without this preflight succeeding),
    # that stops other websites open in the same browser from silently firing
    # requests at this server (e.g. /api/summary or /api/cache from a
    # malicious page while the dashboard is running on localhost).
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self.send_html(200, get_dashboard())
        elif path == "/health":
            from datetime import datetime, timezone
            disk_version = _sha_short(Path(__file__).read_bytes())
            self.send_json(200, {
                "status":                "ok",
                "server_code_version":   SERVER_CODE_VERSION,
                "server_code_on_disk":   disk_version,
                "server_restart_needed": disk_version != SERVER_CODE_VERSION,
                "dashboard_version":     get_dashboard_version(),
                "started_at":            datetime.fromtimestamp(SERVER_STARTED_AT, tz=timezone.utc).isoformat(),
            })
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        if not (self.headers.get("Content-Type") or "").lower().startswith("application/json"):
            self.send_json(415, {"error": "Content-Type must be application/json"}); return
        try:
            payload = self.read_json()
        except Exception:
            self.send_json(400, {"error": "invalid JSON"}); return
        if not isinstance(payload, dict):
            self.send_json(400, {"error": "JSON object expected"}); return

        # -- /api/token: OAuth2 PKCE exchange/refresh — never a password grant.
        #    The dashboard never sees a Viya password: the browser opens
        #    SASLogon's own hosted login page (the "sas.cli" public client's
        #    /SASLogon/oauth/authorize, no redirect_uri — it shows the user a
        #    code to copy back), so SASLogon handles authentication however the
        #    environment requires (plain password, SSO, MFA...). This endpoint
        #    only ever trades that code (or a refresh_token) for an access
        #    token, exactly like the existing /SASLogon/oauth/authorize call —
        #    same public client, same no-secret Basic auth. -------------------
        if path == "/api/token":
            viya_url   = payload.get("url", "").rstrip("/")
            grant_type = payload.get("grant_type", "authorization_code")
            client_id  = payload.get("client_id", "sas.cli")
            if not viya_url:
                self.send_json(400, {"error": "url is required"}); return
            if not _url_allowed(viya_url):
                self.send_json(400, {"error": "Viya URL not allowed"}); return

            if grant_type == "authorization_code":
                code     = payload.get("code", "")
                verifier = payload.get("verifier", "")
                if not code or not verifier:
                    self.send_json(400, {"error": "code and verifier are required"}); return
                form = {
                    "grant_type":    "authorization_code",
                    "code":          code,
                    "code_verifier": verifier,
                    "client_id":     client_id,
                }
            elif grant_type == "refresh_token":
                refresh = payload.get("refresh_token", "")
                if not refresh:
                    self.send_json(400, {"error": "refresh_token is required"}); return
                form = {
                    "grant_type":    "refresh_token",
                    "refresh_token": refresh,
                    "client_id":     client_id,
                }
            else:
                self.send_json(400, {"error": "unsupported grant_type"}); return

            # Logged explicitly (never the code/verifier/refresh_token itself)
            # because this handshake is otherwise invisible to browser-side
            # troubleshooting: the SAS Logon authorize page opens in its own
            # tab/origin, so a HAR captured on the dashboard's own tab never
            # shows it — this exchange, routed through this server, is the
            # one step of sign-in that a local log CAN account for.
            try:
                data = urllib.parse.urlencode(form).encode()
                req = urllib.request.Request(
                    "%s/SASLogon/oauth/token" % viya_url,
                    data=data,
                    headers={
                        "Content-Type":  "application/x-www-form-urlencoded",
                        "Authorization": "Basic " + base64.b64encode(("%s:" % client_id).encode()).decode(),
                    },
                    method="POST",
                )
                with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as r:
                    resp = json.loads(r.read())
                who = _username_from_token(resp.get("access_token", "")) or "?"
                print("  [token] %s OK    url=%s  user=%s" % (grant_type, viya_url, who))
                self.send_json(200, resp)
            except urllib.error.HTTPError as e:
                body = e.read().decode(errors="replace")
                print("  [token] %s FAILED  url=%s  http=%d  %s" % (grant_type, viya_url, e.code, body[:200]))
                self.send_json(e.code, {"error": body})
            except Exception as e:
                print("  [token] %s ERROR  url=%s  %s" % (grant_type, viya_url, e))
                self.send_json(502, {"error": str(e)})
            return

        # -- /api/proxy-all: fetch all pages in parallel, return merged --------
        if path == "/api/proxy-all":
            viya_url  = payload.get("url", "").rstrip("/")
            api_path  = payload.get("path", "")
            bearer    = payload.get("token", "")
            # Derived from the token itself, never trusted from the client — see
            # _username_from_token().
            # (Plain decode is enough here, unlike /api/cache: the very first
            # thing this route does is fetch from Viya with this token, so a
            # forged one is rejected by Viya before any decision uses it.)
            requester = _username_from_token(bearer) or ""
            try:
                page_size = max(1, min(int(payload.get("limit", 100)), 1000))
            except (TypeError, ValueError):
                page_size = 100
            if not api_path:
                self.send_json(400, {"error": "missing path"}); return
            if not _url_allowed(viya_url):
                self.send_json(400, {"error": "Viya URL not allowed"}); return
            api_path = _normalize_api_path(api_path)
            if api_path is None:
                self.send_json(400, {"error": "invalid path"}); return
            # Non-admins may only reach the two endpoints their dashboard uses;
            # the per-chat ownership/redaction rules below then apply to those.
            if not _NON_ADMIN_PATH_RE.match(api_path) and not _is_admin(viya_url, bearer, requester):
                self.send_json(403, {"error": "SAS Administrators only"}); return

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
                    # Bounded so a bogus "count" from the upstream server can't
                    # make this queue an unbounded number of page fetches.
                    starts = range(page_size, min(total, page_size * 10000), page_size)
                    with ThreadPoolExecutor(max_workers=min(8, len(list(starts)))) as pool:
                        futures = {pool.submit(fetch_page, s): s for s in starts}
                        pages   = {}
                        for f in as_completed(futures):
                            pages[futures[f]] = f.result().get("items", [])
                        for s in sorted(pages):
                            result.extend(pages[s])

                # Guard-rail: the chat list itself is scoped to the caller's own
                # chats unless they're a SAS Administrator — only admins get the
                # cross-user "monitor everyone" view.
                if _CHAT_LIST_RE.match(api_path):
                    is_admin = _is_admin(viya_url, bearer, requester)
                    result = _filter_own_chats(result, is_admin, requester)
                    _neutralize_chat_meta(result)

                # Guard-rail: chat-messages listings carry raw function-call
                # arguments/results (which tables/data were touched, actual
                # returned rows). Scrub before it leaves the server.
                elif _CHAT_MESSAGES_RE.search(api_path):
                    is_admin = _is_admin(viya_url, bearer, requester)
                    if not is_admin:
                        # Defense in depth: block a non-admin from reading a
                        # foreign chat's messages even if they reference its ID
                        # directly (e.g. via the Chat ID filter box), bypassing
                        # the list-level filter above.
                        chat_id = api_path.split("?")[0].rstrip("/").split("/")[-2]
                        owner   = _chat_owner(viya_url, bearer, chat_id)
                        if not owner or owner.lower() != (requester or "").lower():
                            self.send_json(403, {"error": "You can only view your own chats"}); return
                    _scrub_chat_messages(result, is_admin)

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
            action   = payload.get("action", "")
            viya_url = payload.get("url", "").rstrip("/")
            bearer   = payload.get("token", "")
            # Security-sensitive for EVERY action here (load, save, patch, clear):
            # which cache file gets touched is decided only by a token Viya
            # itself has accepted (see _verified_username) — never by a
            # client-supplied "user" field, and never by an unverified JWT,
            # either of which could otherwise be crafted to read, poison, or
            # wipe another user's persisted chat history. The environment part
            # of the filename comes from that same URL, not a separate field.
            if not viya_url:
                self.send_json(400, {"error": "url is required"}); return
            user = _verified_username(viya_url, bearer)
            if not user:
                self.send_json(401, {"error": "a valid token is required"}); return
            user    = user.lower()
            cluster = _cluster_from_url(viya_url)
            cf = _cache_filename(cluster, user)
            if action == "load":
                if not cf.exists():
                    self.send_json(200, {"found": False, "data": {}}); return
                try:
                    data = json.loads(cf.read_text(encoding="utf-8"))
                    # Guard-rail: the cache file may have been written while this
                    # user WAS a SAS Administrator. Re-check current admin status
                    # on every load and re-scrub — a persisted cache must never
                    # let a since-demoted user keep seeing old function-call data.
                    is_admin = _is_admin(viya_url, bearer, user)
                    # Guard-rail: a non-admin's persisted cache must never surface
                    # another user's chats either — filter it the same way the
                    # live chat list is filtered, in case it was cached before
                    # this rule existed or while briefly logged in as someone else.
                    data = _filter_own_cache(data, is_admin, user)
                    _neutralize_chat_meta(list(data.values()))
                    for entry in data.values():
                        if isinstance(entry, dict) and isinstance(entry.get("msgs"), list):
                            _scrub_chat_messages(entry["msgs"], is_admin)
                    print("  [cache] load %s  entries=%d  admin=%s" % (cf.name, len(data), is_admin))
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
            # Not an end-user feature (no UI calls it) — it aggregates every
            # user's cache into one cross-user digest (usernames, prompt
            # counts) and returns it straight in the response, which a
            # non-admin must never be able to pull. Meant to be invoked
            # locally (e.g. a scheduled task on this machine), so only
            # loopback callers are allowed.
            if self.client_address[0] not in ("127.0.0.1", "::1"):
                self.send_json(403, {"error": "forbidden"}); return
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

        # -- /api/is-admin: the ONLY place "who is a SAS Administrator" is
        #    decided. The frontend calls this purely to toggle UI visibility;
        #    it never computes admin status itself. -------------------------
        if path == "/api/is-admin":
            viya_url  = payload.get("url", "").rstrip("/")
            bearer    = payload.get("token", "")
            # Identity confirmed by Viya itself, not just decoded from the JWT —
            # otherwise a hand-made token claiming "sasboot" (or an admin whose
            # status is still cached) would be enough. See _verified_username().
            requester = _verified_username(viya_url, bearer)
            is_admin  = bool(requester) and _is_admin(viya_url, bearer, requester)
            # Hint only: a SASAdministrators member who declined to assume the
            # group at sign-in gets the regular-user view; tell the dashboard so
            # it can explain how to get the admin view (sign in again, opt in).
            can_assume = bool(requester) and not is_admin and \
                         _is_admin_group_member(viya_url, bearer, requester)
            self.send_json(200, {"isAdmin": is_admin, "canAssumeAdmin": can_assume})
            return

        # -- /api/pii-words: admin-managed custom PII keyword list -------------
        # Guarded server-side (never trusts the client's "isAdmin" flag) so a
        # demoted or non-admin user can neither read nor overwrite this list
        # even by calling the endpoint directly.
        if path == "/api/pii-words":
            action    = payload.get("action", "")
            viya_url  = payload.get("url", "").rstrip("/")
            bearer    = payload.get("token", "")
            # Identity confirmed by Viya itself — see _verified_username().
            requester = _verified_username(viya_url, bearer)
            if not requester or not _is_admin(viya_url, bearer, requester):
                self.send_json(403, {"error": "SAS Administrators only"}); return

            if action == "load":
                words = _load_pii_words()
                self.send_json(200, {"words": words, "formatted": _format_pii_words(words)})
            elif action == "save":
                text = payload.get("text", "")
                if len(text) > 500:
                    self.send_json(400, {"error": "500 character limit exceeded"}); return
                words = _parse_pii_words(text)
                try:
                    PII_CONFIG.write_text(json.dumps({"words": words}, indent=2), encoding="utf-8")
                    print("  [pii] saved %d custom word(s) by %s" % (len(words), requester))
                    self.send_json(200, {"saved": True, "words": words, "formatted": _format_pii_words(words)})
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

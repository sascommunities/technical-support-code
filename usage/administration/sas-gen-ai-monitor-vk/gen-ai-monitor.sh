#!/usr/bin/env bash
#
# A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
# DATE: 06APR2026
#
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
#  genai-monitor.sh  --  Viya4 GenAI Monitor  (Linux / macOS / server)
#
#  Usage:
#    ./genai-monitor.sh start [--port PORT]
#    ./genai-monitor.sh stop
#    ./genai-monitor.sh restart [--port PORT]
#    ./genai-monitor.sh status
#    ./genai-monitor.sh logs [--lines N]
#    ./genai-monitor.sh help
#
#  Default port : 8899
#  Binds to     : 0.0.0.0 (all interfaces — network accessible)
# =============================================================================

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.genai-monitor.pid"
LOG_FILE="$SCRIPT_DIR/genai-monitor.log"
SERVER_SCRIPT="$SCRIPT_DIR/liveGenAiMonitoring.py"
DASHBOARD_FILE="$SCRIPT_DIR/viya4_dashboard.html"
VENV_DIR="$SCRIPT_DIR/.venv"

# ── Defaults ──────────────────────────────────────────────────────────────────
PORT=8899
LOG_LINES=50
COMMAND=""

# ── Colours (disabled if not a terminal) ──────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

ok()   { echo -e "  ${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "  ${RED}[ERR]${NC}  $*" >&2; }
info() { echo -e "  ${CYAN}[--]${NC}  $*"; }

# ── Parse arguments ───────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    COMMAND="help"
else
    COMMAND="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)   PORT="$2";      shift 2 ;;
        --lines)  LOG_LINES="$2"; shift 2 ;;
        *)        err "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helper: find Python 3 ─────────────────────────────────────────────────────
find_python() {
    if [[ -x "$VENV_DIR/bin/python3" ]]; then
        echo "$VENV_DIR/bin/python3"; return
    fi
    for py in python3 python; do
        if command -v "$py" &>/dev/null; then
            echo "$py"; return
        fi
    done
    err "Python not found. Install Python 3.8+ and add it to PATH."
    exit 1
}

# ── Helper: resolve hostname ──────────────────────────────────────────────────
resolve_hostname() {
    python3 -c \
        "import socket; h=socket.getfqdn(); print(h if h!='localhost' else socket.gethostname())" \
        2>/dev/null \
    || hostname -f 2>/dev/null \
    || echo "localhost"
}

# ── Helper: check if server process is alive ──────────────────────────────────
is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_pid() { cat "$PID_FILE" 2>/dev/null || echo ""; }

# ── Helper: create .venv if missing ───────────────────────────────────────────
setup_venv() {
    local sys_python
    sys_python=$(find_python)

    if [[ -x "$VENV_DIR/bin/python3" ]]; then
        info "Using existing .venv"
        return
    fi

    info "Creating virtual environment in .venv/ ..."
    if "$sys_python" -m venv "$VENV_DIR" &>/dev/null; then
        ok ".venv created"
    else
        warn "Standard venv failed, trying --without-pip ..."
        rm -rf "$VENV_DIR"
        if "$sys_python" -m venv "$VENV_DIR" --without-pip &>/dev/null; then
            ok ".venv created (no pip)"
        else
            warn "Could not create .venv — using system Python"
            return
        fi
    fi

    # Bootstrap pip if missing
    if ! "$VENV_DIR/bin/python3" -m pip --version &>/dev/null 2>&1; then
        info "Bootstrapping pip ..."
        "$VENV_DIR/bin/python3" -m ensurepip --upgrade &>/dev/null || true
        "$VENV_DIR/bin/python3" -m pip install --upgrade pip --quiet &>/dev/null || true
    fi
}

# ── Command: start ────────────────────────────────────────────────────────────
cmd_start() {
    echo ""
    echo -e "${BOLD}  Viya4 GenAI Monitor — Starting${NC}"
    echo "  ────────────────────────────────────────"

    # Required files
    [[ ! -f "$SERVER_SCRIPT"  ]] && { err "Not found: $SERVER_SCRIPT";  exit 1; }
    [[ ! -f "$DASHBOARD_FILE" ]] && { err "Not found: $DASHBOARD_FILE"; exit 1; }

    # Already running?
    if is_running; then
        warn "Already running (PID $(get_pid)). Use 'restart' to restart."
        echo ""
        return
    fi

    setup_venv
    local python
    python=$(find_python)
    info "Python: $python ($($python --version 2>&1))"

    # Free the port if something else is using it
    local existing
    existing=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
    if [[ -n "$existing" ]]; then
        warn "Port $PORT in use by PID $existing — killing ..."
        kill -9 $existing 2>/dev/null || true
        sleep 1
    fi

    # Launch in background, append to log
    info "Starting server on port $PORT ..."
    nohup "$python" "$SERVER_SCRIPT" \
        --server \
        --port "$PORT" \
        --no-browser \
        >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Give it 2 seconds to confirm it's alive
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        ok "Server started (PID $pid)"
        local hostname
        hostname=$(resolve_hostname)
        echo ""
        echo -e "  ${BOLD}Access the dashboard at:${NC}"
        echo -e "  ${GREEN}  Local  :${NC} http://localhost:$PORT"
        echo -e "  ${GREEN}  Network:${NC} http://$hostname:$PORT"
        echo ""
        echo "  Log : $LOG_FILE  (use '$0 logs' to tail)"
        echo "  Stop: $0 stop"
    else
        err "Server failed to start. Last 10 lines of log:"
        echo ""
        tail -10 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || true
        rm -f "$PID_FILE"
        exit 1
    fi
    echo ""
}

# ── Command: stop ─────────────────────────────────────────────────────────────
cmd_stop() {
    echo ""
    echo -e "${BOLD}  Viya4 GenAI Monitor — Stopping${NC}"
    echo "  ────────────────────────────────────────"

    local stopped=0

    # Step 1: PID file
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            info "Killing PID $pid ..."
            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
            sleep 1
            stopped=1
        else
            info "PID $pid not running (stale PID file)"
        fi
        rm -f "$PID_FILE"
    else
        info "No PID file found"
    fi

    # Step 2: Anything left on the port
    local port_pid
    port_pid=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
    if [[ -n "$port_pid" ]]; then
        info "Process $port_pid still on port $PORT — killing ..."
        kill -9 $port_pid 2>/dev/null || true
        stopped=1
    fi

    # Step 3: Verify
    sleep 1
    port_pid=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
    if [[ -n "$port_pid" ]]; then
        warn "Port $PORT still in use by PID $port_pid"
        warn "Try: sudo kill -9 $port_pid"
    else
        ok "Port $PORT is free"
    fi

    echo ""
    if [[ $stopped -eq 1 ]]; then
        ok "Stopped"
    else
        info "Was not running"
    fi
    echo ""
}

# ── Command: restart ──────────────────────────────────────────────────────────
cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

# ── Command: status ───────────────────────────────────────────────────────────
cmd_status() {
    echo ""
    echo -e "${BOLD}  Viya4 GenAI Monitor — Status${NC}"
    echo "  ────────────────────────────────────────"

    if is_running; then
        local pid
        pid=$(get_pid)
        ok "Running (PID $pid)"

        # Uptime
        if command -v ps &>/dev/null; then
            local elapsed
            elapsed=$(ps -o etime= -p "$pid" 2>/dev/null | xargs || true)
            [[ -n "$elapsed" ]] && info "Uptime : $elapsed"
        fi

        # Port binding
        local binding
        binding=$(lsof -Pan -p "$pid" -i tcp 2>/dev/null | grep LISTEN | awk '{print $9}' || true)
        [[ -n "$binding" ]] && info "Listen : $binding"

        local hostname
        hostname=$(resolve_hostname)
        echo ""
        echo -e "  ${BOLD}Access at:${NC}"
        echo -e "    Local   : http://localhost:$PORT"
        echo -e "    Network : http://$hostname:$PORT"
    else
        warn "Not running"
        [[ -f "$PID_FILE" ]] && info "(Stale PID file — will be cleaned on next start)"
    fi

    echo ""
    echo "  Log file : $LOG_FILE"
    echo "  PID file : $PID_FILE"
    echo ""
}

# ── Command: logs ─────────────────────────────────────────────────────────────
cmd_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        warn "No log file found: $LOG_FILE"
        exit 0
    fi
    echo ""
    echo -e "${BOLD}  Viya4 GenAI Monitor — Last $LOG_LINES log lines${NC}"
    echo "  ────────────────────────────────────────"
    echo ""
    tail -"$LOG_LINES" "$LOG_FILE"
    echo ""
}

# ── Command: help ─────────────────────────────────────────────────────────────
cmd_help() {
    echo ""
    echo -e "${BOLD}  Viya4 GenAI Monitor — Management Script${NC}"
    echo ""
    echo "  Usage:  $0 <command> [options]"
    echo ""
    echo "  Commands:"
    printf "    %-30s %s\n" "start [--port PORT]"   "Start the server in the background (default port: 8899)"
    printf "    %-30s %s\n" "stop"                   "Stop the server"
    printf "    %-30s %s\n" "restart [--port PORT]"  "Stop, then start"
    printf "    %-30s %s\n" "status"                 "Show running state, PID, uptime, and access URLs"
    printf "    %-30s %s\n" "logs [--lines N]"       "Tail the log file (default: 50 lines)"
    printf "    %-30s %s\n" "help"                   "Show this help"
    echo ""
    echo "  Examples:"
    echo "    $0 start                   Start on default port 8899"
    echo "    $0 start --port 9000       Start on port 9000"
    echo "    $0 restart --port 9000     Restart on port 9000"
    echo "    $0 status                  Check state and print URLs"
    echo "    $0 logs --lines 100        Show last 100 log lines"
    echo ""
    echo "  Notes:"
    echo "    - Binds to 0.0.0.0 (network accessible). Use a firewall to restrict if needed."
    echo "    - Creates an isolated .venv/ on first start (no root required)."
    echo "    - Logs are appended to: $LOG_FILE"
    echo "    - PID is tracked in:    $PID_FILE"
    echo ""
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
    start)         cmd_start   ;;
    stop)          cmd_stop    ;;
    restart)       cmd_restart ;;
    status)        cmd_status  ;;
    logs)          cmd_logs    ;;
    help|--help|-h) cmd_help  ;;
    *)
        err "Unknown command: '$COMMAND'"
        cmd_help
        exit 1
        ;;
esac

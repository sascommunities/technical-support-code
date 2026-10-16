#!/usr/bin/env bash
#
# A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
# DATE: 15OCT2026
#
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
#  troubleshoot.sh  --  Viya4 GenAI Monitor diagnostics (Linux / macOS)
#
#  Thin launcher only — every actual check lives in troubleshoot.py so this
#  and troubleshoot.bat can never drift apart. Just locates a Python
#  interpreter (same preference order as gen-ai-monitor.sh) and hands off.
#
#  Usage:
#    ./troubleshoot.sh                       Check the local install on port 8899
#    ./troubleshoot.sh --port 9000
#    ./troubleshoot.sh --url http://host:8899   Check a remote/Docker deployment
#    ./troubleshoot.sh --no-log              Skip writing the support log file
#
#  Each run writes troubleshoot_<timestamp>.log (secrets redacted) next to
#  this script — attach it to a support case.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

find_python() {
    if [[ -x "$VENV_DIR/bin/python3" ]]; then
        echo "$VENV_DIR/bin/python3"; return
    fi
    for py in python3 python; do
        if command -v "$py" &>/dev/null; then
            echo "$py"; return
        fi
    done
    echo "ERROR: Python not found. Install Python 3.8+ and add it to PATH." >&2
    exit 1
}

PYTHON="$(find_python)"
exec "$PYTHON" "$SCRIPT_DIR/troubleshoot.py" "$@"

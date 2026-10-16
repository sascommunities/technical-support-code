@echo off
setlocal enabledelayedexpansion

REM A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
REM DATE: 15OCT2026

REM Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
REM SPDX-License-Identifier: Apache-2.0

REM =============================================================================
REM  troubleshoot.bat  --  Viya4 GenAI Monitor diagnostics (Windows)
REM
REM  Thin launcher only — every actual check lives in troubleshoot.py so this
REM  and troubleshoot.sh can never drift apart. Just locates a Python
REM  interpreter and hands off.
REM
REM  Usage:
REM    troubleshoot.bat
REM    troubleshoot.bat --port 9000
REM    troubleshoot.bat --url http://host:8899
REM    troubleshoot.bat --no-log
REM
REM  Each run writes troubleshoot_<timestamp>.log (secrets redacted) next to
REM  this script — attach it to a support case.
REM =============================================================================

cd /d "%~dp0"

set PYTHON=
if exist ".venv\Scripts\python.exe" set PYTHON=.venv\Scripts\python.exe

if "%PYTHON%"=="" (
    for %%P in (python python3) do (
        if "!PYTHON!"=="" (
            where %%P >nul 2>&1
            if !errorlevel! equ 0 set PYTHON=%%P
        )
    )
)

if "%PYTHON%"=="" (
    echo ERROR: Python not found.
    echo Install from https://www.python.org/downloads/
    echo Check "Add Python to PATH" during install.
    pause
    exit /b 1
)

"%PYTHON%" "%~dp0troubleshoot.py" %*
set EXITCODE=%errorlevel%
pause
exit /b %EXITCODE%

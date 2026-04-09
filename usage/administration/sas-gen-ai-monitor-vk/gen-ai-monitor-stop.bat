@echo off
setlocal enabledelayedexpansion

REM A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
REM DATE: 06APR2026

REM Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
REM SPDX-License-Identifier: Apache-2.0

cd /d "%~dp0"
title Viya4 GenAI Monitor - Stopping...

echo.
echo  Stopping Viya4 GenAI Monitor on port 8899...
echo.

set STOPPED=0

:: -- Step 1: Kill by saved PID file -------------------------------------------
if exist ".genai-monitor.pid" (
    set /p PID=<".genai-monitor.pid"
    echo  [1] Killing saved PID !PID!...
    taskkill /PID !PID! /T /F >nul 2>&1
    del ".genai-monitor.pid" >nul 2>&1
    set STOPPED=1
) else (
    echo  [1] No PID file found.
)

:: -- Step 2: Kill whatever is listening on port 8899 --------------------------
echo  [2] Checking port 8899...
for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":8899 " ^| findstr "LISTENING"') do (
    if not "%%a"=="0" (
        echo      Found PID %%a on port 8899 - killing...
        taskkill /PID %%a /T /F >nul 2>&1
        set STOPPED=1
    )
)

:: -- Step 3: Verify port 8899 is free -----------------------------------------
echo  [3] Verifying port 8899 is free...
netstat -ano 2>nul | findstr ":8899 " | findstr "LISTENING" >nul 2>&1
if !errorlevel! equ 0 (
    echo  [WARN] Port 8899 still in use - try running as Administrator.
) else (
    echo  Port 8899 is free.
)

echo.
if "!STOPPED!"=="1" (
    echo  Viya4 GenAI Monitor stopped.
) else (
    echo  Viya4 GenAI Monitor was not running.
)
echo.
timeout /t 3 /nobreak >nul
endlocal
exit

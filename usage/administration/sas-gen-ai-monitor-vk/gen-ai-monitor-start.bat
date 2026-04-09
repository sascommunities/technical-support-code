@echo off
setlocal enabledelayedexpansion

REM A lightweight, browser-based dashboard for monitoring SAS Viya Copilot chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.
REM DATE: 06APR2026

REM Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
REM SPDX-License-Identifier: Apache-2.0

cd /d "%~dp0"
title Viya4 GenAI Monitor - Starting...

:: ?? Find system Python ????????????????????????????????????????????????????????
set SYSPYTHON=
for %%P in (python python3) do (
    if "!SYSPYTHON!"=="" (
        where %%P >nul 2>&1
        if !errorlevel! equ 0 set SYSPYTHON=%%P
    )
)
if "!SYSPYTHON!"=="" (
    echo ERROR: Python not found.
    echo Install from https://www.python.org/downloads/
    echo Check "Add Python to PATH" during install.
    pause & exit /b 1
)
echo Found Python: !SYSPYTHON!

:: ?? Print Python version for diagnostics ?????????????????????????????????????
!SYSPYTHON! --version

:: ?? Check required files ??????????????????????????????????????????????????????
if not exist "liveGenAiMonitoring.py" ( echo ERROR: liveGenAiMonitoring.py missing & pause & exit /b 1 )
if not exist "viya4_dashboard.html"   ( echo ERROR: viya4_dashboard.html missing   & pause & exit /b 1 )

:: ?? Create .venv ??????????????????????????????????????????????????????????????
set PYTHON=
set PYTHONW=

if exist ".venv\Scripts\python.exe" (
    echo Found existing .venv
    set PYTHON="%~dp0.venv\Scripts\python.exe"
    set PYTHONW="%~dp0.venv\Scripts\pythonw.exe"
    goto :venv_ready
)

echo Creating virtual environment...

:: Method 1: standard venv
!SYSPYTHON! -m venv .venv
if exist ".venv\Scripts\python.exe" (
    echo .venv created OK - method 1
    set PYTHON="%~dp0.venv\Scripts\python.exe"
    set PYTHONW="%~dp0.venv\Scripts\pythonw.exe"
    goto :venv_bootstrap_pip
)

:: Method 2: venv --without-pip (Microsoft Store Python)
echo Method 1 failed, trying without pip...
if exist ".venv" rmdir /s /q ".venv" >nul 2>&1
!SYSPYTHON! -m venv .venv --without-pip
if exist ".venv\Scripts\python.exe" (
    echo .venv created OK - method 2
    set PYTHON="%~dp0.venv\Scripts\python.exe"
    set PYTHONW="%~dp0.venv\Scripts\pythonw.exe"
    goto :venv_bootstrap_pip
)

:: Method 3: virtualenv package
echo Method 2 failed, trying virtualenv package...
if exist ".venv" rmdir /s /q ".venv" >nul 2>&1
!SYSPYTHON! -m pip install virtualenv --quiet
!SYSPYTHON! -m virtualenv .venv
if exist ".venv\Scripts\python.exe" (
    echo .venv created OK - method 3
    set PYTHON="%~dp0.venv\Scripts\python.exe"
    set PYTHONW="%~dp0.venv\Scripts\pythonw.exe"
    goto :venv_ready
)

:: All methods failed - fall back to system Python
echo WARNING: Could not create .venv - using system Python instead.
echo Your system Python packages will not be affected (only pyyaml may be added).
set PYTHON=!SYSPYTHON!
set PYTHONW=
goto :venv_ready

:venv_bootstrap_pip
:: Bootstrap pip if missing inside venv
!PYTHON! -m pip --version >nul 2>&1
if !errorlevel! neq 0 (
    echo Bootstrapping pip in .venv...
    !PYTHON! -m ensurepip --upgrade >nul 2>&1
    !PYTHON! -m pip install --upgrade pip --quiet >nul 2>&1
)

:venv_ready
echo Using Python: !PYTHON!

:: ?? Install dependencies ??????????????????????????????????????????????????????
!PYTHON! -c "import yaml" >nul 2>&1
if !errorlevel! neq 0 (
    echo Installing pyyaml...
    if exist "requirements.txt" (
        !PYTHON! -m pip install -r requirements.txt --quiet
    ) else (
        !PYTHON! -m pip install pyyaml --quiet
    )
    if !errorlevel! neq 0 (
        echo ERROR: Failed to install pyyaml. Check internet connection.
        pause & exit /b 1
    )
    echo pyyaml installed OK.
)

:: ?? Kill any existing instances ???????????????????????????????????????????????
echo Stopping any existing instances...
for %%V in (pythonw.exe pythonw3.13.exe pythonw3.12.exe pythonw3.11.exe pythonw3.10.exe pythonw3.9.exe pythonw3.8.exe) do (
    taskkill /F /FI "IMAGENAME eq %%V" >nul 2>&1
)
for %%P in (8080 8081 8082) do (
    for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":%%P " ^| findstr "LISTENING"') do (
        if not "%%a"=="0" taskkill /PID %%a /T /F >nul 2>&1
    )
)
timeout /t 1 /nobreak >nul

:: Fixed port
set PORT=8899
echo Using port !PORT!

:: ?? Start server ?????????????????????????????????????????????????????????????
echo Starting server...
!PYTHON! "%~dp0liveGenAiMonitoring.py" --launch --port !PORT!

if !errorlevel! neq 0 (
    echo.
    echo ERROR: Server failed to start.
    echo Check genai-monitor.log for details:
    echo   %~dp0genai-monitor.log
    echo.
    if exist "%~dp0genai-monitor.log" (
        echo Last 20 lines of log:
        echo ----------------------------------------
        !PYTHON! -c "lines=open(r'%~dp0genai-monitor.log').readlines(); print(''.join(lines[-20:]), end='')"
        echo ----------------------------------------
    )
    pause & exit /b 1
)

:: ?? Open browser ?????????????????????????????????????????????????????????????
timeout /t 2 /nobreak >nul
start "" http://localhost:!PORT!

echo.
echo Viya4 GenAI Monitor running on http://localhost:!PORT!
echo Browser opened. To stop, run stop-genai-monitor.bat
echo.
timeout /t 6 /nobreak >nul
endlocal
exit

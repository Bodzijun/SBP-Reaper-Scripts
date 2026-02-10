@echo off
REM VO QC Server Launcher for Windows
REM This script starts the Flask server for voice-over quality control

setlocal enabledelayedexpansion

REM Find the script directory
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

REM Find venv in parent directories (SBP-Reaper-Scripts/.venv)
if exist "..\..\.venv\Scripts\python.exe" (
    echo Found venv in parent directory
    set PYTHON=..\..\.venv\Scripts\python.exe
) else if exist "..\.venv\Scripts\python.exe" (
    set PYTHON=..\.venv\Scripts\python.exe
) else if exist ".venv\Scripts\python.exe" (
    set PYTHON=.venv\Scripts\python.exe
) else (
    echo Python venv not found. Trying system Python...
    set PYTHON=python.exe
)

echo.
echo ============================================
echo   VO QC Server v1.0
echo ============================================
echo.
echo Using Python: %PYTHON%
echo Directory: %SCRIPT_DIR%
echo.
echo Starting server on http://localhost:5000
echo Press Ctrl+C to stop
echo.
echo ============================================
echo.

REM Run the Flask server
call "%PYTHON%" vo_qc_server.py

pause

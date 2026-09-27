@echo off
setlocal enabledelayedexpansion

title SHAPNEST — Prototype Distance Web Application Launcher

echo ===============================================================================
echo            SHAPNEST — PHASE 1 DISTANCE PROTOTYPE LAUNCHER
echo ===============================================================================
echo.
echo  Target: 5-Node Distance Measurement & Central Hub Display
echo  Port  : http://localhost:8000
echo.

:: Check if port 8000 is already in use
netstat -ano | findstr :8000 >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [INFO] Port 8000 is already active (Local server running).
    echo [INFO] Launching default web browser...
    start http://localhost:8000
    goto finish
)

:: Check for Python
where python >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [OK] Python detected. Starting static HTTP server on port 8000...
    start "SHAPNEST Web Server" /B python -m http.server 8000 --directory "%~dp0"
    timeout /t 2 /nobreak >nul
    echo [OK] Server started. Opening browser...
    start http://localhost:8000
    goto finish
)

:: Check for Node.js / npx
where npx >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [OK] Node.js/npx detected. Starting server...
    start "SHAPNEST Web Server" /B npx -y serve -l 8000 "%~dp0"
    timeout /t 2 /nobreak >nul
    echo [OK] Server started. Opening browser...
    start http://localhost:8000
    goto finish
)

echo [ERROR] Neither Python nor Node.js was found on PATH.
echo Please install Python 3 or Node.js to serve the application,
echo or open index.html directly in Google Chrome / Microsoft Edge.
echo.
pause
exit /b 1

:finish
echo.
echo ===============================================================================
echo  Application is running at: http://localhost:8000
echo  
echo  Instructions:
echo   1. To connect to Central Hub: Click "CONNECT SERIAL (HUB)" and select COM port.
echo   2. To test in browser without hardware: Click "DEMO SIMULATION".
echo   3. Dynamic Distance Toggle: Click "m" or "cm" in the header to switch units.
echo   4. To close server: Close this window or terminate Python process.
echo ===============================================================================
echo.
pause

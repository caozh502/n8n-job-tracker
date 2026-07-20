@echo off
title n8n Job Tracker
cd /d "E:\Caleb_Space\Code\n8n-job-tracker"

echo ========================================
echo   n8n Job Tracker — 一键启动
echo ========================================
echo.

:: Kill any existing n8n / scraper processes
echo [1/3] Cleaning up old processes...
taskkill /f /im n8n.cmd 2>nul
taskkill /f /im node.exe 2>nul
timeout /t 2 /nobreak >nul

:: Start scraper server (background)
echo [2/3] Starting JobSpy scraper server...
start "Scraper" cmd /c "node scraper_server.js"

:: Start n8n
echo [3/3] Starting n8n...
echo.
echo n8n will be available at: http://localhost:5678
echo Scraper running on: http://localhost:3456
echo.
echo ========================================
echo   Waiting for n8n to start...
echo   (This may take 1-2 minutes)
echo ========================================
echo.

node "C:\c\Users\Caleb Tsao\npm-global\node_modules\n8n\bin\n8n" start --port=5678

pause

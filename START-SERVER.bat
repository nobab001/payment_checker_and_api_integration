@echo off
title Payment Checker API (port 3000)
cd /d "%~dp0server"
echo.
echo ========================================
echo   Payment Checker - Node API Server
echo   Folder: %cd%
echo   URL:    http://localhost:3000
echo ========================================
echo.
if not exist node_modules (
  echo Installing npm packages...
  call npm install
)
echo Phone on same Wi-Fi uses: http://YOUR_PC_IP:3000
echo   (see lib\config\api_config.dart kDevLanHost — run ipconfig for IPv4)
echo.
echo If the phone still cannot connect, run ALLOW-FIREWALL.bat as Administrator once.
echo.
echo Starting server... (this window must stay open)
echo.
node app.js
pause

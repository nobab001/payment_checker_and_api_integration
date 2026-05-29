@echo off
title Payment Checker - Dev stack
cd /d "%~dp0"
echo.
echo Starting API server in a new window...
start "Payment Checker API" cmd /k "%~dp0START-SERVER.bat"
echo.
echo If your phone cannot connect on Wi-Fi, run ALLOW-FIREWALL.bat as Administrator.
echo Then hot-restart the Flutter app (R).
echo.
pause

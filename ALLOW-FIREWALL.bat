@echo off
:: Run as Administrator: right-click -> Run as administrator
title Payment Checker - Firewall (port 3000)
echo.
echo Allowing inbound TCP port 3000 for LAN devices (phone on same Wi-Fi)...
echo.
netsh advfirewall firewall delete rule name="Payment Checker API" >nul 2>&1
netsh advfirewall firewall add rule name="Payment Checker API" dir=in action=allow protocol=TCP localport=3000
if errorlevel 1 (
  echo FAILED. Right-click this file and choose "Run as administrator".
  pause
  exit /b 1
)
echo OK - phones can reach http://YOUR_PC_IP:3000
echo.
pause

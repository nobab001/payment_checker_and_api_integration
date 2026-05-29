@echo off
title Payment Checker ngrok tunnel
echo.
echo ========================================
echo   ngrok tunnel -> localhost:3000
echo   Keep this window OPEN while testing app
echo ========================================
echo.
echo After ngrok starts, copy the https://....ngrok-free.dev URL
echo into lib\config\api_config.dart (kBaseUrl) and rebuild the app.
echo.
ngrok http 3000
pause

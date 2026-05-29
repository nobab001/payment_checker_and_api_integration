# Reads ngrok local API and updates lib/config/api_config.dart
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'lib\config\api_config.dart'

try {
    $json = Invoke-RestMethod -Uri 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 5
    $https = $json.tunnels | Where-Object { $_.proto -eq 'https' } | Select-Object -First 1
    if (-not $https) { throw 'No https tunnel found. Run START-NGROK.bat first.' }
    $url = $https.public_url.TrimEnd('/')
} catch {
    Write-Host "ERROR: Could not read ngrok. Start ngrok first (START-NGROK.bat)." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

$content = Get-Content $configPath -Raw
$newContent = $content -replace "const String kBaseUrl = '[^']*';", "const String kBaseUrl = '$url';"
Set-Content -Path $configPath -Value $newContent -NoNewline

Write-Host "Updated kBaseUrl -> $url" -ForegroundColor Green
Write-Host "Now run: flutter run -t lib/main_user.dart" -ForegroundColor Yellow

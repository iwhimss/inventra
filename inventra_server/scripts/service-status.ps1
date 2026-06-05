# ─── Inventra Server — Servis Durum Kontrolü ────────────────────────────────
# Kullanım: .\scripts\service-status.ps1

$serviceName = "InventraServer"
$root = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Inventra Server — Durum" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Servis durumu
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "  Servis     : $($svc.Status)" -ForegroundColor $color
    Write-Host "  Başlangıç  : $($svc.StartType)" -ForegroundColor Gray
} else {
    Write-Host "  Servis     : Kurulu değil" -ForegroundColor Yellow
    Write-Host "  Kurmak için: .\scripts\install-service.ps1" -ForegroundColor Cyan
}

Write-Host ""

# Port dinleme
Write-Host "  Port Durumu (5000):" -ForegroundColor Gray
$listening = netstat -an 2>$null | Select-String ":5000 "
if ($listening) {
    Write-Host "  ✓ Port 5000 dinleniyor" -ForegroundColor Green
    $listening | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "  ✗ Port 5000 dinlenmiyor" -ForegroundColor Red
}

Write-Host ""

# Health check
try {
    $response = Invoke-WebRequest -Uri "http://localhost:5000/health" -TimeoutSec 3 -ErrorAction Stop
    $json = $response.Content | ConvertFrom-Json
    Write-Host "  Health     : ✓ OK ($($json.status))" -ForegroundColor Green
} catch {
    Write-Host "  Health     : ✗ Bağlanamadı (http://localhost:5000/health)" -ForegroundColor Red
}

Write-Host ""

# Log dosyası durumu
$logFile = Join-Path $root "build\logs\stdout.log"
if (Test-Path $logFile) {
    $logSize = [math]::Round((Get-Item $logFile).Length / 1KB, 1)
    $logModified = (Get-Item $logFile).LastWriteTime
    Write-Host "  Log        : $logFile" -ForegroundColor Gray
    Write-Host "  Log Boyutu : $logSize KB (son: $logModified)" -ForegroundColor Gray
}

Write-Host ""

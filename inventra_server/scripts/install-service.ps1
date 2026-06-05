# ─── Inventra Server — Windows Servis Kurulumu (NSSM) ────────────────────────
# Yönetici olarak çalıştırın: Sağ tık → "PowerShell'i Yönetici olarak çalıştır"
# Kullanım: .\scripts\install-service.ps1

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $root "build\inventra_server.exe"
$logsPath = Join-Path $root "build\logs"
$serviceName = "InventraServer"

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Inventra Server — Servis Kurulumu     " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── 1. Derleme kontrolü ──────────────────────────────────────────────────────
if (-not (Test-Path $exePath)) {
    Write-Host "✗ Derlenmiş exe bulunamadı: $exePath" -ForegroundColor Red
    Write-Host "  Önce derleme yapın: .\scripts\build.ps1" -ForegroundColor Yellow
    exit 1
}

# ─── 2. NSSM kontrolü ─────────────────────────────────────────────────────────
$nssmPath = ""
$candidates = @(
    "$root\scripts\nssm.exe",
    "C:\nssm\nssm.exe",
    "C:\tools\nssm\nssm.exe",
    (Get-Command nssm -ErrorAction SilentlyContinue)?.Source
) | Where-Object { $_ -and (Test-Path $_) }

if ($candidates.Count -gt 0) {
    $nssmPath = $candidates[0]
    Write-Host "✓ NSSM bulundu: $nssmPath" -ForegroundColor Green
} else {
    Write-Host "✗ NSSM bulunamadı!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  NSSM indirmek için:" -ForegroundColor Yellow
    Write-Host "  → https://nssm.cc/download" -ForegroundColor White
    Write-Host ""
    Write-Host "  İndirdikten sonra nssm.exe'yi şuraya koyun:" -ForegroundColor Yellow
    Write-Host "  → $root\scripts\nssm.exe" -ForegroundColor White
    Write-Host ""
    Write-Host "  Veya Chocolatey ile: choco install nssm" -ForegroundColor Gray
    exit 1
}

# ─── 3. Mevcut servisi kaldır ─────────────────────────────────────────────────
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "→ Mevcut '$serviceName' servisi kaldırılıyor..." -ForegroundColor Yellow
    & $nssmPath stop $serviceName 2>$null
    & $nssmPath remove $serviceName confirm
}

# ─── 4. Servisi kur ───────────────────────────────────────────────────────────
Write-Host "→ Servis kuruluyor..." -ForegroundColor Yellow

& $nssmPath install $serviceName $exePath

# Çalışma dizini (exe'nin bulunduğu yer — data/ bu dizine göredir)
& $nssmPath set $serviceName AppDirectory (Join-Path $root "build")

# Log dosyaları
if (-not (Test-Path $logsPath)) { New-Item -ItemType Directory -Path $logsPath | Out-Null }
& $nssmPath set $serviceName AppStdout "$logsPath\stdout.log"
& $nssmPath set $serviceName AppStderr "$logsPath\stderr.log"
& $nssmPath set $serviceName AppRotateFiles 1
& $nssmPath set $serviceName AppRotateSeconds 86400       # Günlük rotasyon
& $nssmPath set $serviceName AppRotateBytesHigh 0
& $nssmPath set $serviceName AppRotateByteesLow 10485760  # 10 MB

# Crash sonrası yeniden başlatma (5 saniye bekle)
& $nssmPath set $serviceName AppRestartDelay 5000

# Servis açıklaması
& $nssmPath set $serviceName Description "Inventra POS Server - Self-hosted point of sale backend"

# Otomatik başlatma
Set-Service -Name $serviceName -StartupType Automatic

# ─── 5. Servisi başlat ────────────────────────────────────────────────────────
Write-Host "→ Servis başlatılıyor..." -ForegroundColor Yellow
& $nssmPath start $serviceName

Start-Sleep -Seconds 2
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host ""
    Write-Host "✓ Servis başarıyla kuruldu ve çalışıyor!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Servis adı   : $serviceName" -ForegroundColor White
    Write-Host "  Exe          : $exePath" -ForegroundColor Gray
    Write-Host "  Log dizini   : $logsPath" -ForegroundColor Gray
    Write-Host "  Başlangıç    : Otomatik (Windows ile birlikte)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Logları izlemek için: .\scripts\view-logs.ps1" -ForegroundColor Cyan
    Write-Host "  Kaldırmak için:       .\scripts\uninstall-service.ps1" -ForegroundColor Cyan
} else {
    Write-Host "⚠ Servis kuruldu fakat çalışmıyor. Log dosyasını kontrol edin:" -ForegroundColor Yellow
    Write-Host "   $logsPath\stderr.log" -ForegroundColor White
}

Write-Host ""

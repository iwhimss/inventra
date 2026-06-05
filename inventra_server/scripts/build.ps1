# ─── Inventra Server — Derleme Scripti ───────────────────────────────────────
# Kullanım: .\scripts\build.ps1
# Çalıştırma politikası sorunları için: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

param(
    [string]$OutputDir = "build"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Inventra Server — Derleme             " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Build klasörünü oluştur
$buildPath = Join-Path $root $OutputDir
if (-not (Test-Path $buildPath)) {
    New-Item -ItemType Directory -Path $buildPath | Out-Null
}

Write-Host "→ Kaynak: $root" -ForegroundColor Gray
Write-Host "→ Çıktı:  $buildPath\inventra_server.exe" -ForegroundColor Gray
Write-Host ""

# Dart compile
Write-Host "Derleniyor..." -ForegroundColor Yellow
Set-Location $root
dart compile exe bin/server.dart -o "$buildPath\inventra_server.exe"

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Derleme başarısız!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Derleme tamamlandı: $buildPath\inventra_server.exe" -ForegroundColor Green
Write-Host ""

# Mevcut data/ dizinini kopyala (varsa)
$dataSrc = Join-Path $root "data"
$dataDst = Join-Path $buildPath "data"
if (Test-Path $dataSrc) {
    Write-Host "→ data/ dizini kopyalanıyor..." -ForegroundColor Gray
    if (-not (Test-Path $dataDst)) {
        Copy-Item -Path $dataSrc -Destination $dataDst -Recurse
    } else {
        Write-Host "  (build/data/ zaten mevcut, atlandı)" -ForegroundColor Gray
    }
}

# logs/ klasörünü oluştur (servis için)
$logsPath = Join-Path $buildPath "logs"
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath | Out-Null
    Write-Host "✓ build\logs\ klasörü oluşturuldu" -ForegroundColor Green
}

Write-Host ""
Write-Host "Sonraki adım: Servisi kurmak için şunu çalıştırın:" -ForegroundColor Cyan
Write-Host "   .\scripts\install-service.ps1" -ForegroundColor White
Write-Host ""

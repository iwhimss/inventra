# ─── Inventra Server — Windows Servis Kaldırma ────────────────────────────────
# Yönetici olarak çalıştırın.
# Kullanım: .\scripts\uninstall-service.ps1

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$serviceName = "InventraServer"

$nssmPath = ""
$candidates = @(
    "$root\scripts\nssm.exe",
    "C:\nssm\nssm.exe",
    "C:\tools\nssm\nssm.exe",
    (Get-Command nssm -ErrorAction SilentlyContinue)?.Source
) | Where-Object { $_ -and (Test-Path $_) }

if ($candidates.Count -gt 0) {
    $nssmPath = $candidates[0]
}

$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host "Servis zaten kurulu değil: $serviceName" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "→ '$serviceName' servisi durduruluyor..." -ForegroundColor Yellow

if ($nssmPath) {
    & $nssmPath stop $serviceName 2>$null
    Start-Sleep -Seconds 1
    & $nssmPath remove $serviceName confirm
} else {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null
}

Write-Host "✓ Servis kaldırıldı." -ForegroundColor Green
Write-Host "  Not: build\ ve data\ dizinleri korundu — veriler silinmedi." -ForegroundColor Gray
Write-Host ""

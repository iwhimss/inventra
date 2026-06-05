# ─── Inventra Server — Log Görüntüleyici ────────────────────────────────────
# Sunucu loglarını canlı olarak terminalde gösterir.
# Kullanım: .\scripts\view-logs.ps1
# Çıkmak için Ctrl+C

param(
    [int]$Lines = 80,
    [switch]$StdErr
)

$root = Split-Path -Parent $PSScriptRoot
$logsPath = Join-Path $root "build\logs"

if ($StdErr) {
    $logFile = Join-Path $logsPath "stderr.log"
    $label = "HATA LOGU"
} else {
    $logFile = Join-Path $logsPath "stdout.log"
    $label = "SUNUCU LOGU"
}

if (-not (Test-Path $logFile)) {
    Write-Host ""
    Write-Host "Log dosyası bulunamadı: $logFile" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Servis kurulu değilse: .\scripts\install-service.ps1" -ForegroundColor Cyan
    Write-Host "Geliştirici modunda çalışıyorsa start.bat'ı kullanın." -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Inventra Server — $label" -ForegroundColor Cyan
Write-Host "   $logFile" -ForegroundColor Gray
Write-Host "   Çıkmak için Ctrl+C" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Get-Content $logFile -Wait -Tail $Lines

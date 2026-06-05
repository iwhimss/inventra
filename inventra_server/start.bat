@echo off
title Inventra Server
cd /d "%~dp0"

:: İlk çalıştırma: data/config.json yoksa kurulum başlat
if not exist "data\config.json" (
  echo.
  echo  Kurulum bulunamadi. Ilk kurulum baslatiliyor...
  echo.
  dart run bin/server.dart --setup
  echo.
  echo  Kurulum tamamlandi. Sunucuyu baslatmak icin bu dosyayi tekrar calistirin.
  pause
  exit /b
)

dart run bin/server.dart

echo.
echo  Sunucu durdu. Kapatmak icin bir tusa basin...
pause

@echo off
title Inventra Server
cd /d "%~dp0"

:MENU
cls
echo.
echo  ╔══════════════════════════════════════╗
echo  ║        Inventra Server v0.1.0        ║
echo  ╚══════════════════════════════════════╝
echo.

:: İlk çalıştırma kontrolü
if not exist "data\config.json" (
  echo  Kurulum bulunamadi. Ilk kurulum baslatiliyor...
  echo.
  dart run bin/server.dart --setup
  echo.
  echo  Kurulum tamamlandi. Sunucuyu baslatmak icin tekrar calistirin.
  echo.
  pause
  exit /b
)

echo  [1] Sunucuyu Baslat
echo  [2] Ayarlari Yeniden Yapilandir  ^(veriler korunur^)
echo  [3] Sifirla ve Yeniden Kur       ^(TUM VERILER SILINIR^)
echo  [4] Servis Loglarini Goruntule
echo  [5] Cikis
echo.
set /p CHOICE="  Seciminiz [1-5]: "

if "%CHOICE%"=="1" goto START
if "%CHOICE%"=="2" goto RECONFIGURE
if "%CHOICE%"=="3" goto RESET
if "%CHOICE%"=="4" goto LOGS
if "%CHOICE%"=="5" exit /b
goto MENU

:START
echo.
dart run bin/server.dart
echo.
echo  Sunucu durdu.
pause
goto MENU

:RECONFIGURE
echo.
echo  Mevcut ayarlar korunarak yapilandirma ekrani aciliyor...
echo  ^(Bos birakilanlar mevcut degerle kalir^)
echo.
dart run bin/server.dart --setup
echo.
pause
goto MENU

:RESET
echo.
dart run bin/server.dart --reset
echo.
pause
goto MENU

:LOGS
echo.
if exist "build\logs\stdout.log" (
  echo  Canli log akisi basliyor... ^(Ctrl+C ile dur^)
  echo  ────────────────────────────────────────
  powershell -Command "Get-Content 'build\logs\stdout.log' -Wait -Tail 50"
) else (
  echo  Log dosyasi bulunamadi.
  echo  Servis kurulu degilse: scripts\install-service.ps1 calistirin.
)
echo.
pause
goto MENU

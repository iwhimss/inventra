#!/bin/bash
# Inventra Server — Linux/macOS başlatma scripti
# VDS (systemd servisi) için örnek:
#   sudo cp inventra-server.service /etc/systemd/system/
#   sudo systemctl enable inventra-server
#   sudo systemctl start inventra-server

cd "$(dirname "$0")"

# İlk çalıştırma: data/config.json yoksa kurulum başlat
if [ ! -f "data/config.json" ]; then
  echo ""
  echo "Kurulum bulunamadı. İlk kurulum başlatılıyor..."
  echo ""
  dart run bin/server.dart --setup
  echo ""
  echo "Kurulum tamamlandı. Sunucuyu başlatmak için scripti tekrar çalıştırın."
  exit 0
fi

dart run bin/server.dart

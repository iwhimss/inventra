# Inventra Server — VDS/VPS Kurulum Kılavuzu

Bu kılavuz, `inventra_server`'ı bir VDS veya VPS sunucusuna (Ubuntu 22.04 LTS önerilir) adım adım kurmanızı sağlar.

---

## İçindekiler

1. [Gereksinimler](#1-gereksinimler)
2. [Dart SDK Kurulumu](#2-dart-sdk-kurulumu)
3. [Projeyi İndir](#3-projeyi-i̇ndir)
4. [İlk Kurulum (Setup Wizard)](#4-i̇lk-kurulum-setup-wizard)
5. [Firewall Ayarları](#5-firewall-ayarları)
6. [Sunucuyu Çalıştır](#6-sunucuyu-çalıştır)
7. [systemd ile Otomatik Başlatma](#7-systemd-ile-otomatik-başlatma)
8. [İsteğe Bağlı: Docker ile Kurulum](#8-i̇steğe-bağlı-docker-ile-kurulum)
9. [İsteğe Bağlı: Nginx + SSL (HTTPS)](#9-i̇steğe-bağlı-nginx--ssl-https)
10. [Flutter Uygulamasını Bağla](#10-flutter-uygulamasını-bağla)
11. [Güncelleme Prosedürü](#11-güncelleme-prosedürü)
12. [Sorun Giderme](#12-sorun-giderme)

---

## 1. Gereksinimler

| Bileşen | Minimum | Önerilen |
|---|---|---|
| OS | Ubuntu 20.04 LTS | Ubuntu 22.04 LTS |
| RAM | 512 MB | 1 GB |
| Disk | 1 GB | 5 GB |
| CPU | 1 vCPU | 2 vCPU |
| Dart SDK | 3.0+ | Son kararlı sürüm |
| SQLite | 3.x | Son kararlı sürüm |

---

## 2. Dart SDK Kurulumu

### 2.1 APT ile kur (Ubuntu/Debian)

```bash
# GPG anahtarını ekle
sudo apt-get update
sudo apt-get install -y apt-transport-https gnupg2

wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
  | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg

echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' \
  | sudo tee /etc/apt/sources.list.d/dart_stable.list

# Dart'ı kur
sudo apt-get update
sudo apt-get install -y dart
```

### 2.2 SQLite bağımlılıklarını kur

```bash
sudo apt-get install -y libsqlite3-dev sqlite3
```

### 2.3 Kurulumu doğrula

```bash
dart --version
# Dart SDK version: 3.x.x (stable)

sqlite3 --version
# 3.x.x ...
```

---

## 3. Projeyi İndir

```bash
# inventra kullanıcısı oluştur (güvenlik için önerilir)
sudo useradd -m -s /bin/bash inventra
sudo su - inventra

# Projeyi klonla
git clone https://github.com/iwhimss/inventra.git
cd inventra/inventra_server

# Bağımlılıkları yükle
dart pub get
```

---

## 4. İlk Kurulum (Setup Wizard)

Setup wizard, `config.json` ve ilk admin kullanıcısını oluşturur. **Sunucuyu ilk kez başlatmadan önce bir kez çalıştırılmalıdır.**

```bash
dart run bin/server.dart --setup
```

Wizard size şunları soracak:

```
=== Inventra Server — İlk Kurulum ===

İşletme adı: Örnek Market
Admin personel ID (varsayılan: 1000): 1000
Admin şifre: ••••••••
Port (varsayılan: 5000): 5000
Ağ erişimi:
  0 — Sadece bu cihaz (127.0.0.1)
  1 — Tüm ağ (0.0.0.0)  ← VDS için bu seçeneği seçin
Seçim: 1
```

Kurulum tamamlandığında `data/config.json` oluşur:

```json
{
  "name": "Örnek Market",
  "port": 5000,
  "host": "0.0.0.0",
  "api_key": "inv_xxxxxxxxxxxxxxxxxxxx",
  "created_at": "2026-06-05T...",
  "api_version": "1"
}
```

> `data/` klasörü `.gitignore`'da hariç tutulmuştur — config ve veritabanı git'e yüklenmez.

---

## 5. Firewall Ayarları

### 5.1 UFW (Ubuntu Firewall)

```bash
# UFW'yi etkinleştir (SSH'ı kapatma)
sudo ufw allow OpenSSH
sudo ufw enable

# Inventra server portunu aç
sudo ufw allow 5000/tcp

# Durumu kontrol et
sudo ufw status
```

### 5.2 Cloud Provider Firewall

Hetzner, DigitalOcean, AWS vb. sağlayıcılar kendi panel firewall'larına da sahiptir. Panel → Firewall → **Inbound Rules** kısmından `TCP 5000` portunu açın.

---

## 6. Sunucuyu Çalıştır

### Manuel başlatma

```bash
cd ~/inventra/inventra_server

# Varsayılan ayarlarla başlat (config.json'daki host/port kullanılır)
dart run bin/server.dart

# Sadece localhost (test için)
dart run bin/server.dart --local

# Port geçersiz kılma
dart run bin/server.dart --port 8080

# Host geçersiz kılma
dart run bin/server.dart --host 0.0.0.0
```

Sunucu başarıyla başladığında:

```
Inventra Server çalışıyor → http://0.0.0.0:5000
```

### Bağlantıyı test et

Başka bir makineden:
```bash
curl http://<VDS_IP>:5000/api/version
# {"server_version":"0.0.1","api_version":"1","min_app_version":"0.0.1"}
```

---

## 7. systemd ile Otomatik Başlatma

Sunucunun VDS yeniden başladığında otomatik olarak ayağa kalkması için systemd servisi oluşturun.

### 7.1 Dart binary yolunu bul

```bash
which dart
# /usr/bin/dart  veya  /usr/lib/dart/bin/dart
```

### 7.2 Servis dosyası oluştur

```bash
sudo nano /etc/systemd/system/inventra-server.service
```

Aşağıdaki içeriği yapıştırın (Dart yolunu ve kullanıcı adını kendi ortamınıza göre düzenleyin):

```ini
[Unit]
Description=Inventra POS Server
After=network.target

[Service]
Type=simple
User=inventra
WorkingDirectory=/home/inventra/inventra/inventra_server
ExecStart=/usr/bin/dart run bin/server.dart
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### 7.3 Servisi etkinleştir ve başlat

```bash
sudo systemctl daemon-reload
sudo systemctl enable inventra-server
sudo systemctl start inventra-server

# Durumu kontrol et
sudo systemctl status inventra-server
```

### 7.4 Log takibi

```bash
# Canlı log
sudo journalctl -u inventra-server -f

# Son 100 satır
sudo journalctl -u inventra-server -n 100
```

---

## 8. İsteğe Bağlı: Docker ile Kurulum

Docker tercih ediyorsanız Dart SDK ve manuel kurulum gerekmez. Veriler Docker volume'da saklanır; container silinse veya güncellenmiş olsa bile veriler korunur.

### 8.1 Docker ve Docker Compose Kur

```bash
# Docker Engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Kurulumu doğrula
docker --version
docker compose version
```

### 8.2 Projeyi İndir

```bash
git clone https://github.com/iwhimss/inventra.git
cd inventra
```

### 8.3 İlk Kurulum: ENV Değişkenleri

`docker-compose.yml` dosyasını açın ve ilk kurulum için yorum satırlarını kaldırın:

```yaml
environment:
  - TZ=Europe/Istanbul
  - INVENTRA_BUSINESS_NAME=Mağazam
  - INVENTRA_ADMIN_ID=1000
  - INVENTRA_ADMIN_PASSWORD=güvenli_şifre_buraya
  - INVENTRA_PORT=5000
  - INVENTRA_HOST=0.0.0.0
```

### 8.4 Container'ı Başlat

```bash
# İmajı derle ve başlat
docker compose up -d --build

# Durumu kontrol et
docker compose ps

# Logları takip et
docker compose logs -f inventra-server
```

İlk başlangıçta sunucu ENV değişkenlerinden kurulumu otomatik tamamlar:

```
🐳 Docker otomatik kurulum başlatılıyor...
   İşletme: Mağazam
   Admin ID: 1000
   Port: 5000 / Host: 0.0.0.0
✓ Otomatik kurulum tamamlandı
✓ API Key: inv_xxxxxxxxxxxxxxxxxxxx
```

### 8.5 Kurulum Sonrası ENV Temizliği

Kurulum tamamlandıktan sonra `docker-compose.yml`'den hassas bilgileri kaldırın:

```bash
# ENV satırlarını yorum satırına al
nano docker-compose.yml
# → INVENTRA_BUSINESS_NAME ve diğer satırları # ile başlatın

# Container'ı ENV güncellemesiyle yeniden başlat
docker compose up -d
```

### 8.6 Verilerin Yedeklenmesi

```bash
# Volume içeriğini yedekle
docker run --rm \
  -v inventra_inventra_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/inventra-backup-$(date +%Y%m%d).tar.gz /data
```

### 8.7 Güncelleme (Docker)

```bash
git pull origin main
docker compose build --no-cache
docker compose up -d
```

> **Not:** `docker-compose.yml` içindeki `ports: "5000:5000"` satırını değiştirerek farklı dış port kullanabilirsiniz. Örneğin `"80:5000"` ile HTTP varsayılan portuna yönlendirin.

---

## 9. İsteğe Bağlı: Nginx + SSL (HTTPS)

Sunucunuza bir domain bağladıysanız HTTPS üzerinden erişim sağlayabilirsiniz.

### 8.1 Nginx ve Certbot kur

```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### 8.2 Nginx site konfigürasyonu

```bash
sudo nano /etc/nginx/sites-available/inventra
```

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/inventra /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 8.3 SSL sertifikası al

```bash
sudo certbot --nginx -d your-domain.com
```

Certbot Nginx konfigürasyonunu otomatik olarak günceller. Sertifikalar 90 günde bir otomatik yenilenir.

> **Not:** `inventra-server.service` dosyasında `host` değerini `0.0.0.0` yerine `127.0.0.1` olarak değiştirin — Nginx proxy üzerinden erişildiğinde dışarıya doğrudan port açmanıza gerek kalmaz.

---

## 10. Flutter Uygulamasını Bağla

1. Inventra uygulamasını açın.
2. **Sunucu Bağlantısı** ekranında şu formatları kullanabilirsiniz:
   - Doğrudan IP: `<VDS_IP>:5000`
   - Domain (HTTP): `your-domain.com`
   - Domain (HTTPS, Nginx varsa): `your-domain.com`
3. **Bağlan** tuşuna basın — cihaz eşleme isteği sunucuya gönderilir.
4. Sunucunun yönetici Windows uygulamasında **Ayarlar → Cihazlar** ekranına gidin.
5. Bekleyen eşleme isteğini onaylayın.
6. Onay sonrası uygulama otomatik olarak giriş ekranına geçer.

---

## 11. Güncelleme Prosedürü

```bash
# inventra kullanıcısına geç
sudo su - inventra
cd ~/inventra

# Güncellemeleri çek
git pull origin main

# Bağımlılıkları güncelle
cd inventra_server
dart pub get

# Servisi yeniden başlat
sudo systemctl restart inventra-server

# Durumu kontrol et
sudo systemctl status inventra-server
```

> `data/config.json` ve `data/inventra.db` git tarafından takip edilmez — güncelleme sırasında silinmez.

---

## 12. Sorun Giderme

### Port erişilemiyor

```bash
# Portun dinlenip dinlenmediğini kontrol et
ss -tlnp | grep 5000

# UFW durumu
sudo ufw status

# Servis loglarına bak
sudo journalctl -u inventra-server -n 50
```

### "dart: command not found"

```bash
# Dart'ın PATH'te olup olmadığını kontrol et
echo $PATH

# Dart'ı PATH'e ekle (gerekirse)
export PATH="$PATH:/usr/lib/dart/bin"
echo 'export PATH="$PATH:/usr/lib/dart/bin"' >> ~/.bashrc
source ~/.bashrc
```

### SQLite hatası

```bash
# libsqlite3 paketinin kurulu olup olmadığını kontrol et
dpkg -l | grep sqlite3
sudo apt-get install -y libsqlite3-dev
```

### Uygulama bağlanamıyor

1. VDS IP ve portu doğru girildi mi? (`<IP>:5000`)
2. Cloud provider firewall panelinde port 5000 TCP açık mı?
3. `curl http://<VDS_IP>:5000/api/version` komutu VDS üzerinden çalışıyor mu?
4. Servis çalışıyor mu? `sudo systemctl status inventra-server`

---

*Inventra POS — [github.com/iwhimss/inventra](https://github.com/iwhimss/inventra)*

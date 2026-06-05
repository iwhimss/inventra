# Inventra Server — VDS/VPS Kurulum Kılavuzu

**v0.1.0** · Bu kılavuz, `inventra_server`'ı bir VDS veya VPS sunucusuna (Ubuntu 22.04 LTS önerilir) adım adım kurmanızı sağlar.

> Geliştirme ortamında çalıştırmak için: [docs/development.md](development.md)

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
10. [Admin Paneli (Web Dashboard)](#10-admin-paneli-web-dashboard)
11. [Flutter Uygulamasını Bağla](#11-flutter-uygulamasını-bağla)
12. [Güncelleme Prosedürü](#12-güncelleme-prosedürü)
13. [Sorun Giderme](#13-sorun-giderme)

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
  "api_version": "1.0"
}
```

> `data/` klasörü `.gitignore`'da hariç tutulmuştur — config ve veritabanı git'e yüklenmez.

### Kurulumu sıfırlama

Kurulumu baştan yapmak veya test sonrası temizlemek için:

```bash
dart run bin/server.dart --reset
```

Onay sorusu sonrasında `data/config.json`, `data/inventra.db` ve tüm resimler/loglar silinir; ardından setup wizard otomatik çalışır.

> ⚠️ Bu komut **tüm satış ve ürün verilerini kalıcı olarak siler.** Üretim ortamında dikkatli kullanın.

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

# Port geçersiz kılma (config.json değişmez, tek seferlik)
dart run bin/server.dart --port 8080

# Host geçersiz kılma
dart run bin/server.dart --host 0.0.0.0

# Tüm seçenekler
dart run bin/server.dart --help
```

Sunucu başarıyla başladığında:

```
  📂 Data dizini : /home/inventra/inventra/inventra_server/data
  🏪 İşletme     : Örnek Market
  🌐 Adres       : 0.0.0.0:5000

Inventra Server çalışıyor → http://0.0.0.0:5000
Çıkmak için Ctrl+C basın.
```

### Bağlantıyı test et

Başka bir makineden:
```bash
curl http://<VDS_IP>:5000/health
# {"status":"ok","uptime_seconds":5}

curl http://<VDS_IP>:5000/api/version
# {"server_version":"0.1.0","api_version":"1.0","min_app_version":"0.1.0"}
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

## 9. İsteğe Bağlı: Nginx + SSL (HTTPS) + Cloudflare

Sunucunuza bir domain bağladıysanız HTTPS üzerinden erişim sağlayabilirsiniz.

---

### 9.A Cloudflare ile Kurulum (Önerilen)

Cloudflare kullanıyorsanız bu bölümü takip edin. Cloudflare HTTPS'i kendi edge'inde sonlandırır; origin sunucusunda (VDS) SSL sertifikası **gerekmez**.

#### 9.A.1 — Cloudflare SSL modunu ayarla

```
Cloudflare Dashboard → inventra.fatihdikec.me → SSL/TLS → Overview
→ "Flexible" seç
```

> **Neden Flexible?**  
> Cloudflare → VDS bağlantısı HTTP (port 80) üzerinden olur. Tarayıcı yine de HTTPS görür çünkü Cloudflare edge'inde SSL sonlandırır.  
> "Full" mod seçilirse Cloudflare port **443**'e bağlanır — VDS'de port 443 bloğu ve SSL sertifikası olmadan Nginx yanlış server block'a düşerek başka bir subdomain'in içeriğini sunar.

#### 9.A.2 — Nginx kur ve yapılandır

```bash
sudo apt-get install -y nginx
```

```bash
sudo nano /etc/nginx/sites-available/inventra
```

Aşağıdaki konfigürasyonu **eksiksiz** yapıştırın (`your-domain.com` yerine kendi domain'inizi yazın):

```nginx
# WebSocket için map değişkeni.
# Normal HTTP isteklerine Connection:close, WebSocket'e Connection:upgrade gönderir.
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        $connection_upgrade;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
```

> ⚠️ **Önemli:** Bu konfigürasyonda yalnızca `listen 80` bloğu olmalıdır.  
> `listen 443 ssl` bloğu **eklemeyin** — Cloudflare Flexible modunda 443'e bağlanmaz, eklenmesi yanlış server block eşlemesine (başka subdomain içeriği) ve sertifika hatalarına yol açar.

```bash
# Symlink oluştur (ilk kurulumsa)
sudo ln -s /etc/nginx/sites-available/inventra /etc/nginx/sites-enabled/

# Mevcut default site'ı devre dışı bırak (çakışmayı önler)
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t
sudo systemctl reload nginx
```

---

### 9.B Cloudflare Olmadan Kurulum (Direkt SSL)

Cloudflare kullanmıyorsanız Certbot ile origin'de SSL sertifikası alın.

#### 9.B.1 — Nginx ve Certbot kur

```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

#### 9.B.2 — Nginx konfigürasyonu (port 80)

```bash
sudo nano /etc/nginx/sites-available/inventra
```

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        $connection_upgrade;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/inventra /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

#### 9.B.3 — SSL sertifikası al (Certbot)

```bash
sudo certbot --nginx -d your-domain.com
```

Certbot port 443 bloğunu otomatik ekler ve HTTP→HTTPS yönlendirmesi kurar. Sertifikalar 90 günde bir otomatik yenilenir.

---

### 9.C Mevcut Bozuk Kurumu Düzeltme

`"güvenli değil" + başka subdomain içeriği` hatası alıyorsanız aşağıdaki adımları uygulayın:

**1 — Cloudflare modunu Flexible'a alın:**
```
Cloudflare → SSL/TLS → Overview → Flexible
```

**2 — Nginx konfigürasyonunu kontrol edin ve port 443 bloğunu silin:**
```bash
sudo nano /etc/nginx/sites-available/inventra
```
`server { listen 443 ssl; ... }` bloğunu **tamamen silin**, sadece `listen 80` bloğu kalmalı.

**3 — Nginx'i yeniden yükleyin:**
```bash
sudo nginx -t
sudo systemctl reload nginx
```

**4 — Docker image'ı güncelleyin:**
```bash
cd ~/inventra
git pull origin main
docker compose down
docker compose up -d --build
```

**5 — Test edin:**
```bash
curl http://localhost:5000/health
# Tarayıcıda: https://your-domain.com/admin/login
```

> **Not:** `jrwhims.fatihdikec.me` gibi başka bir subdomain'in Nginx config'inde `default_server` işareti varsa kaldırmanız önerilir:  
> `listen 80 default_server;` → `listen 80;`

---

## 10. Admin Paneli (Web Dashboard)

Sunucu çalışırken tarayıcıdan erişin:

```
http://<VDS_IP>:5000/admin
```

Nginx + SSL kuruluysa:
```
https://your-domain.com/admin
```

Setup sırasında belirlediğiniz Staff ID ve şifre ile giriş yapın.

### Panel Sayfaları

| Sayfa | Açıklama |
|-------|----------|
| **Dashboard** | Uptime, günlük ciro, stok uyarıları, 7 günlük satış özeti |
| **Ürünler** | Stok ve fiyat inline düzenleme, stok seviyesi renk kodlaması |
| **Satışlar** | Bugün / hafta / ay / tümü filtreli satış geçmişi |
| **Loglar** | Tipe göre filtrelenebilir aktivite logları |
| **Cihazlar** | Eşleme isteklerini onayla / reddet |
| **Kullanıcılar** | POS terminali kullanıcıları yönet |
| **Ayarlar** | İşletme bilgileri, port/host yapılandırması, API key, sıfırlama |

### Port/Host Değiştirme (Admin Panelinden)

1. **Ayarlar** → **Sunucu Yapılandırması**
2. Yeni port veya host seçeneğini girin
3. **Yapılandırmayı Kaydet** → sunucuyu yeniden başlatın

> Değişiklikler `data/config.json`'a yazılır. Geçerli olması için `systemctl restart inventra-server` gerekir.

---

## 11. Flutter Uygulamasını Bağla

1. Inventra uygulamasını açın.
2. **Sunucu Bağlantısı** ekranında şu formatları kullanabilirsiniz:
   - Doğrudan IP: `<VDS_IP>:5000`
   - Domain (HTTP): `your-domain.com`
   - Domain (HTTPS, Nginx varsa): `your-domain.com`
3. **Bağlan** tuşuna basın — cihaz eşleme isteği sunucuya gönderilir.
4. Tarayıcıda admin panelini açın: `http://<VDS_IP>:5000/admin` → **Cihazlar**
5. Bekleyen eşleme isteğini **Onayla** tuşuyla onaylayın.
6. Onay sonrası uygulama otomatik olarak giriş ekranına geçer.

---

## 12. Güncelleme Prosedürü

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

## 13. Sorun Giderme

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

*Inventra POS v0.1.0 — [github.com/iwhimss/inventra](https://github.com/iwhimss/inventra)*

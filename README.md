# Inventra POS

**v0.1.0** · Küçük ve orta ölçekli işletmeler için offline-first satış noktası (POS) sistemi. Flutter tabanlı masaüstü/mobil uygulama ve Dart HTTP sunucusundan oluşur.

---

## Özellikler

- **Stok Yönetimi** — Ürün ekleme, düzenleme, kategori ve birim desteği, ondalık miktar/stok takibi
- **Çoklu Barkod** — Bir ürüne birden fazla barkod (alias) tanımlama; tedarikçi barkodu değişse de ürün kaybolmaz
- **POS Ekranı** — Hızlı satış, sepet, barkod okuma desteği, fiyat teklifi PDF'i
- **Müşteri & Tedarikçi** — Cari hesap takibi
- **Kasa Yönetimi** — Açılış/kapanış, günlük rapor
- **Raporlar & Analitik** — Satış grafikleri, stok özeti
- **Etiket Tasarımcısı** — Özelleştirilebilir ürün etiketi şablonları
- **Otomatik Yedekleme** — Kullanıcılar, şablonlar, Excel, müşteri verileri
- **Cihaz Eşleştirme** — QR/IP tabanlı güvenli cihaz pairing sistemi
- **Çoklu Cihaz** — Tek sunucu, birden fazla POS terminali
- **Offline Destek** — İnternet kesintisinde yerel SQLite ile çalışmaya devam eder

---

## Mimari

```
┌─────────────────────┐         ┌──────────────────────────┐
│   inventra_app      │  HTTP   │     inventra_server       │
│   Flutter Desktop   │ ──────► │     Dart / Shelf          │
│   Windows / Linux   │ ◄────── │     REST API + WebSocket  │
│   Android (beta)    │         │                           │
└─────────────────────┘         └───────────┬──────────────┘
                                            │
                                    ┌───────▼────────┐
                                    │  inventra.db   │
                                    │  SQLite        │
                                    └────────────────┘
```

- **inventra_app** — Riverpod state yönetimi, SQLite yerel önbellek, WebSocket anlık senkronizasyon
- **inventra_server** — Shelf HTTP çerçevesi, cihaz pairing, admin paneli (web tabanlı)
- **Veritabanı** — Her iki tarafta SQLite; sunucu kayıt kaynağı, uygulama offline önbellek olarak kullanır

---

## Gereksinimler

### Sunucu (`inventra_server`)

- Dart SDK ≥ 3.0
- SQLite 3.x (`libsqlite3-dev`)
- Windows veya Linux

### Uygulama (`inventra_app`)

- Flutter ≥ 3.x
- Windows (birincil platform), Linux, Android (beta)

---

## Hızlı Başlangıç

### 1. Sunucuyu Kur ve Başlat

```bash
cd inventra_server

# Bağımlılıkları yükle
dart pub get

# İlk kurulum (işletme adı, admin şifre, port seçimi)
dart run bin/server.dart --setup

# Sunucuyu başlat
dart run bin/server.dart
```

Sunucu varsayılan olarak port `5000`'de başlar.

```
Inventra Server çalışıyor → http://0.0.0.0:5000
```

#### Diğer Başlatma Seçenekleri

```bash
dart run bin/server.dart --local        # Sadece bu cihaz (127.0.0.1)
dart run bin/server.dart --port 8080    # Farklı port
dart run bin/server.dart --host 0.0.0.0 # Tüm ağ arayüzleri
dart run bin/server.dart --reset        # TÜM VERİLERİ SİL, sıfırdan kur
```

Windows için `start.bat` (menülü), Linux için `start.sh` kısayol scriptleri mevcuttur.

#### Docker ile Başlatma

```bash
# docker-compose.yml içinde ENV değişkenlerini ayarlayın (ilk kurulum için)
docker compose up -d --build

# Logları izle
docker compose logs -f inventra-server
```

#### Windows Servis Olarak Çalıştırma

```powershell
# Önce NSSM indirin: https://nssm.cc/download → scripts/nssm.exe
cd inventra_server
.\scripts\build.ps1           # Exe'ye derle
.\scripts\install-service.ps1  # Windows servisi olarak kur
.\scripts\view-logs.ps1       # Logları canlı izle
```

### 2. Uygulamayı Çalıştır

```bash
cd inventra_app

# Bağımlılıkları yükle
flutter pub get

# Windows'ta çalıştır
flutter run -d windows
```

### 3. Bağlan

1. Uygulama açıldığında **Sunucu Bağlantısı** ekranı görünür.
2. Sunucu IP ve portunu girin: `192.168.1.100:5000`
3. Sunucu yönetici panelinden veya Windows POS uygulamasından cihazı onaylayın.
4. Giriş ekranında admin kimlik bilgileriyle (varsayılan: `1000` / setup sırasında belirlediğiniz şifre) giriş yapın.

---

## VDS/VPS Üzerinde Çalıştırma

Sunucuyu bir bulut sunucusunda çalıştırmak için adım adım kurulum kılavuzuna bakın:

[docs/vds-deployment.md](docs/vds-deployment.md)

Kılavuz şunları kapsar:
- Dart SDK kurulumu (Ubuntu/Debian)
- Setup wizard ve config.json yapısı
- Firewall ayarları (UFW + cloud provider)
- systemd servisi ile otomatik başlatma
- **Docker ile kurulum** (Dockerfile + docker-compose + ENV otomatik kurulum)
- Nginx reverse proxy + Let's Encrypt SSL
- Güncelleme prosedürü

---

## Proje Yapısı

```
inventra/
├── inventra_server/          # Dart HTTP sunucu
│   ├── bin/server.dart       # Giriş noktası (CLI: --setup, --reset, --port, ...)
│   ├── lib/
│   │   ├── core_server.dart  # HTTP router ve 50+ handler
│   │   ├── setup.dart        # Kurulum wizard (interaktif + ENV/Docker)
│   │   ├── database_helper.dart
│   │   └── web_admin/        # Tarayıcı tabanlı admin paneli
│   │       └── admin_handler.dart  # Dashboard, Ürünler, Satışlar, Loglar, Ayarlar
│   ├── scripts/              # Windows servis yönetimi (NSSM)
│   │   ├── build.ps1         # dart compile exe
│   │   ├── install-service.ps1
│   │   ├── uninstall-service.ps1
│   │   ├── view-logs.ps1
│   │   └── service-status.ps1
│   ├── Dockerfile            # Multi-stage Docker image
│   ├── .dockerignore
│   ├── start.bat             # Windows menülü kısayol
│   └── start.sh              # Linux kısayol
│
├── inventra_app/             # Flutter uygulaması
│   ├── lib/
│   │   ├── core/             # Tema, veritabanı, servisler, widget'lar
│   │   └── features/         # Ekranlar (POS, stok, müşteri, ayarlar...)
│   └── windows/              # Windows platform dosyaları
│
├── docker-compose.yml        # Docker Compose (kalıcı volume dahil)
├── docs/
│   ├── vds-deployment.md     # VDS + Docker kurulum kılavuzu
│   └── project-overview.md   # Proje mimarisi detaylı özet
├── .plan/                    # Geliştirme planları (versiyon bazlı)
└── README.md
```

---

## Web Admin Paneli

Sunucu çalıştıktan sonra tarayıcıdan `http://<sunucu-ip>:5000/admin` adresine erişin.

| Sayfa | Açıklama |
|-------|----------|
| **Dashboard** | Çalışma süresi, bugünkü ciro, stok uyarıları, 7 günlük satış özeti |
| **Ürünler** | Stok ve fiyat inline düzenleme, stok seviyesine göre renk kodlaması, arama/filtreleme |
| **Satışlar** | Satış geçmişi (bugün/hafta/ay/tümü), toplam ciro, ödeme türü |
| **Loglar** | Aktivite logları (auth/ürün/satış/kasa/sistem tipine göre filtrelenebilir) |
| **Cihazlar** | Eşleme isteklerini onaylama/reddetme, bağlı cihazlar, cihaz yeniden adlandırma |
| **Kullanıcılar** | Kullanıcı ekleme/silme |
| **Ayarlar** | İşletme bilgileri, port/host düzenleme, API key görüntüleme, güncelleme kontrolü (minimum uygulama sürümü), sıfırlama |

---

## Cihaz Eşleştirme Sistemi

Güvenlik için her uygulama kurulumu sunucuya bir **pairing request** gönderir:

1. Uygulama benzersiz `device_id` (UUID) oluşturur.
2. `/api/pair/request` endpoint'ine cihaz adı ve tipiyle istek gönderir.
3. Sunucu isteği `pending` durumunda saklar.
4. Yönetici admin panelinden veya başka bir POS terminalinden isteği onaylar.
5. Onay sonrası uygulama bir `api_key` alır; tüm sonraki istekler bu anahtarla imzalanır.

---

## Güvenlik

- Şifreler SHA-256 ile hashlenir; düz metin hiçbir zaman saklanmaz veya iletilmez.
- API anahtarları cihaz bazında düzenlenir; her terminal bağımsız olarak iptal edilebilir.
- Sunucu `0.0.0.0` (tüm ağ) veya `127.0.0.1` (yalnızca yerel) modlarında çalıştırılabilir.

---

## Lisans

MIT — Ayrıntılar için [LICENSE](LICENSE) dosyasına bakın.

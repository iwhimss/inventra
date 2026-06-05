# Inventra POS

Küçük ve orta ölçekli işletmeler için offline-first satış noktası (POS) sistemi. Flutter tabanlı masaüstü/mobil uygulama ve Dart HTTP sunucusundan oluşur.

---

## Özellikler

- **Stok Yönetimi** — Ürün ekleme, düzenleme, kategori ve birim desteği
- **POS Ekranı** — Hızlı satış, sepet, barkod okuma desteği
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
```

Windows için `start.bat`, Linux için `start.sh` kısayol scriptleri mevcuttur.

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
- Nginx reverse proxy + Let's Encrypt SSL
- Güncelleme prosedürü

---

## Proje Yapısı

```
inventra/
├── inventra_server/          # Dart HTTP sunucu
│   ├── bin/server.dart       # Giriş noktası (CLI)
│   ├── lib/
│   │   ├── core_server.dart  # HTTP router ve handler'lar
│   │   ├── setup.dart        # İlk kurulum wizard'ı
│   │   ├── database_helper.dart
│   │   └── web_admin/        # Tarayıcı tabanlı admin paneli
│   ├── start.bat             # Windows kısayol
│   └── start.sh              # Linux kısayol
│
├── inventra_app/             # Flutter uygulaması
│   ├── lib/
│   │   ├── core/             # Tema, veritabanı, servisler, widget'lar
│   │   └── features/         # Ekranlar (POS, stok, müşteri, ayarlar...)
│   └── windows/              # Windows platform dosyaları
│
├── docs/
│   └── vds-deployment.md     # VDS kurulum kılavuzu
├── .plan/                    # Geliştirme planları (versiyon bazlı)
└── README.md
```

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

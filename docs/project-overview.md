# Inventra POS — Detaylı Proje Analizi

---

## Genel Mimari

Inventra iki bağımsız uygulamadan oluşan bir yerel ağ POS sistemidir:

```
┌──────────────────────┐  HTTP + WebSocket  ┌───────────────────────────┐
│    inventra_app      │ ─────────────────► │     inventra_server       │
│  Flutter (Windows/   │ ◄───────────────── │  Dart + Shelf HTTP        │
│  Android/Linux/iOS)  │                    │  REST API + WS + Web Admin│
└──────────────────────┘                    └────────────┬──────────────┘
                                                         │
                                                 ┌───────▼────────┐
                                                 │  inventra.db   │
                                                 │  SQLite (17    │
                                                 │  tablo)        │
                                                 └────────────────┘
```

Sunucu LAN'da (veya VDS'de) çalışır. Uygulama aynı ağdaki herhangi bir cihazdan bağlanabilir. İnternet bağlantısı **zorunlu değil** — sistem tamamen offline-first tasarlanmıştır.

---

## Proje Dosya Yapısı

```
inventra/
├── inventra_server/              ← Dart standalone sunucu
│   ├── bin/server.dart           ← CLI giriş noktası
│   ├── lib/
│   │   ├── core_server.dart      ← Tüm HTTP router + handler'lar (~2113 satır)
│   │   ├── database_helper.dart  ← SQLite wrapper (sqlite3 paketi)
│   │   ├── setup.dart            ← Kurulum sihirbazı
│   │   ├── server_paths.dart     ← Exe/dev path tespiti
│   │   └── web_admin/
│   │       └── admin_handler.dart ← Server-side HTML admin paneli
│   └── data/                     ← .gitignore'da (runtime)
│       ├── config.json           ← Sunucu konfigürasyonu
│       ├── inventra.db           ← SQLite veritabanı
│       └── server.log            ← İstek logları
│
├── inventra_app/                 ← Flutter uygulaması
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── database/         ← App SQLite helper (sqflite)
│       │   ├── models/           ← Product, Sale, User, Customer, Supplier...
│       │   ├── network/          ← ApiClient, WebSocketService, SyncManager
│       │   ├── services/         ← AutoBackup, CartTransfer, Sound, Version
│       │   ├── theme/            ← AppTheme, ThemeProvider
│       │   └── widgets/          ← CustomTitleBar, ortak bileşenler
│       └── features/
│           ├── auth/             ← Login, ServerConnect
│           ├── pos/              ← Satış ekranı, sepet
│           ├── product/          ← Ürün listesi ve yönetimi
│           ├── analytics/        ← Dashboard, raporlar, satış geçmişi
│           ├── clients/          ← Müşteri + tedarikçi + cari işlemler
│           ├── cash_register/    ← Vardiya yönetimi
│           ├── receipt/          ← Etiket tasarımı, PDF, termal yazıcı
│           ├── settings/         ← 4 sekme ayar paneli
│           ├── logs/             ← Aktivite log ekranı
│           └── dashboard/        ← MainDashboard (sol menü + içerik)
│
├── docs/
│   ├── vds-deployment.md         ← VDS kurulum kılavuzu
│   └── project-overview.md       ← Bu dosya
├── .plan/                        ← Versiyon bazlı geliştirme planları
├── README.md
└── LICENSE (MIT)
```

---

## inventra_server — Nasıl Çalışır?

### Başlatma

```bash
dart run bin/server.dart [--setup] [--port 5000] [--host 0.0.0.0] [--local]
```

`bin/server.dart` CLI argümanlarını parse eder:
- `--setup` → Kurulum sihirbazını başlatır (ilk çalıştırmada yapılır)
- `--port` / `--host` → `config.json`'daki değerleri geçersiz kılar
- `--local` → Host'u `127.0.0.1`'e kilitler (sadece bu cihaz)

Başlatmada `data/config.json` okunur. Buradaki `host`, `port`, `api_key` çalışma parametrelerini belirler.

### Request Pipeline

Her gelen istek şu zincirden geçer:

```
İstek → _apiKeyMiddleware → fileLogger → Cascade(adminHandler, mainRouter)
```

1. **`_apiKeyMiddleware`**: `X-Api-Key` header'ını kontrol eder. Muaf olan path'ler: `/health`, `/api/pair/request`, `/api/pair/status/*`, `/api/version`, `/admin/*`, `/images/*`, `/api/ws`
2. **`fileLogger`**: Her isteği `data/server.log`'a yazar
3. **`adminHandler`**: `/admin/*` path'lerini yakalar (cookie session ile)
4. **`mainRouter`**: Tüm `/api/*` endpoint'leri handle eder

### Setup Wizard

`dart run bin/server.dart --setup` komutu çalıştırıldığında `lib/setup.dart` devreye girer:

1. İşletme adı sorar
2. Admin staff_id ve şifresi alır (SHA-256 ile hash'lenir, düz metin hiçbir zaman saklanmaz)
3. Port (varsayılan 5000) ve host (`0.0.0.0` = tüm ağ, `127.0.0.1` = sadece bu cihaz)
4. Şunları oluşturur:
   - `data/config.json` → sunucu konfigürasyonu + `inv_<uuid>` formatında API key
   - `data/inventra.db` → tüm tablolar + admin kullanıcı + varsayılan roller (owner, cashier)

---

## Server Veritabanı Şeması (18 Tablo)

| Tablo | Amaç | Önemli Sütunlar |
|---|---|---|
| `products` | Ürün kataloğu (ana barkod) | barcode, name, sale_price, purchase_price, sale_price_2, sale_price_3, stock, critical_stock_level, vat_rate, unit, product_group, is_fast_product, image_path, shelf_location |
| `product_barcodes` | Çoklu barkod havuzu (alias) — bir ürünün ana barkodu dışındaki ek barkodları | product_id (FK), barcode, created_at |
| `product_groups` | Ürün kategorileri | name, color |
| `sales` | Satış başlıkları | total_amount, paid_amount, payment_method, cash_amount, card_amount, cashier_id, discount |
| `sale_items` | Satış kalemleri | sale_id, product_id, quantity, unit_price, discount, total_price |
| `users` | Personel | staff_id (UNIQUE), password_hash (SHA-256), name, role, permissions |
| `roles` | Yetki rolleri | name, permissions (JSON) |
| `settings` | Sistem ayarları | key-value çiftleri (işletme adı, KDV, api_key, vb.) |
| `paired_devices` | Bağlı cihazlar | device_id, device_name, device_type, status (pending/approved), api_key |
| `cart_transfers` | Sepet transferleri | sender_device_id, target_device_id, cart_data (JSON), status |
| `customers` | Müşteriler | name, phone, email, address, tax_office, tax_number |
| `suppliers` | Tedarikçiler | name, phone, email, address, tax_office, tax_number |
| `client_transactions` | Cari hesap işlemleri | client_id, client_type, amount, transaction_type, payment_method |
| `activity_logs` | Kullanıcı aktivite logu | module, user_id, action, target, description |
| `stock_history` | Stok değişim geçmişi | product_id, old_stock, new_stock, change_amount, reason, user_name |
| `cash_shifts` | Vardiya | status (open/closed), opening_balance, closing_balance, total_cash_sales, total_card_sales |
| `label_templates` | Etiket şablonları | name, config (JSON — etiket tasarım verisi) |
| `events` | Değişiklik olayları | type, table_name, record_id, data, device_id (delta sync için) |

**Migration sistemi** mevcut: 13 migration adımı, `PRAGMA table_info` ile sütun varlığı kontrol edilerek çalışır (destructive değil, additive).

---

## Tam HTTP Endpoint Listesi

### Auth gerektirmeyen

| Method | Path | İşlev |
|---|---|---|
| GET | `/health` | Sunucu sağlık kontrolü |
| POST | `/api/pair/request` | Cihaz eşleme isteği gönder |
| GET | `/api/pair/status/<device_id>` | Eşleme durumu sorgula |
| GET | `/api/version` | Sunucu versiyon bilgisi |
| GET | `/images/<filename>` | Ürün görseli serve et |
| GET/POST | `/admin/*` | Web admin paneli (cookie session) |

### `X-Api-Key` header gerektiren

| Method | Path | İşlev |
|---|---|---|
| GET | `/api/ws` | WebSocket bağlantısı |
| GET/POST | `/api/products` | Ürün listele / oluştur |
| PUT/DELETE | `/api/products/<id>` | Ürün güncelle / sil |
| POST | `/api/products/<id>/image` | Görsel yükle (base64) |
| DELETE | `/api/products/<id>/image` | Görsel sil |
| GET | `/api/products/by-barcode/<barcode>` | Ana veya alias barkoddan ürün ara |
| GET | `/api/products/<id>/barcodes` | Ürünün alias barkod havuzunu listele |
| POST | `/api/products/<id>/barcodes` | Ürüne alias barkod ekle (çakışmada `conflict:true` döner) |
| DELETE | `/api/products/<id>/barcodes/<barcodeId>` | Alias barkod sil |
| GET | `/api/product-barcodes` | Tüm alias barkodları toplu çek (client-side önbellekleme) |
| POST | `/api/products/bulk-import` | Toplu ürün aktarımı |
| POST | `/api/products/stock` | Toplu stok güncelleme |
| POST | `/api/products/bulk-price` | Toplu fiyat güncelleme |
| POST | `/api/products/bulk-delete` | Toplu silme |
| POST | `/api/products/bulk-fast` | Hızlı ürün toggle |
| GET/POST | `/api/sales` | Satış listele / oluştur (stok otomatik düşer) |
| GET | `/api/sales/<id>/items` | Satış kalemlerini getir |
| DELETE | `/api/sales/<id>` | Satış sil |
| POST | `/api/sales/clear` | Tüm satışları sil |
| GET | `/api/analytics/today` | Bugünkü ciro + son 50 satış |
| GET | `/api/reports` | Dönemsel rapor (Günlük/Haftalık/Aylık/Yıllık) |
| GET/POST/DELETE | `/api/product-groups` | Grup yönetimi |
| GET/POST/PUT/DELETE | `/api/users` | Kullanıcı yönetimi |
| GET/POST/PUT/DELETE | `/api/roles` | Rol yönetimi |
| GET/POST | `/api/settings` / `/api/settings/bulk` | Ayar yönetimi |
| GET/POST/DELETE | `/api/label-templates` | Etiket şablonları |
| GET | `/api/pair/pending` | Bekleyen eşleme istekleri |
| POST | `/api/pair/approve` / `/api/pair/reject` | Cihaz onayla / reddet |
| GET | `/api/pair/devices` | Onaylı cihaz listesi |
| POST | `/api/cart/transfer` | Sepet transferi gönder |
| GET | `/api/cart/transfer/pending` | Bekleyen transferler |
| POST | `/api/cart/transfer/ack` | Transfer alındı bildir |
| POST | `/api/cart/transfer/respond` | Transfer kabul / reddet |
| GET | `/api/cart/transfer/status/<id>` | Transfer durumu |
| POST | `/api/auth/login` | Personel girişi |
| GET | `/api/sync/snapshot` | Tam veri snapshot (ilk sync) |
| GET/POST/PUT/DELETE | `/api/customers` | Müşteri yönetimi |
| GET/POST/PUT/DELETE | `/api/suppliers` | Tedarikçi yönetimi |
| GET/POST/DELETE | `/api/client-transactions` | Cari işlem yönetimi |
| GET/POST | `/api/logs/activity` | Aktivite logları |
| GET | `/api/logs/stock` | Stok geçmişi |
| POST | `/api/cash/open` | Vardiya aç |
| POST | `/api/cash/close` | Vardiya kapat |
| GET | `/api/cash/current` | Aktif vardiya |
| GET | `/api/cash/history` | Vardiya geçmişi |
| GET | `/api/check-update` | Delta sync metadata (`?table=products`) |
| POST | `/api/admin/push-event` | WebSocket broadcast tetikle |

---

## Flutter App ↔ Server İletişimi

### HTTP Katmanı

`ApiClient` singleton (`http` paketi). Her istekte 3 header gider:
- `X-Api-Key: inv_<uuid>` → Ana kimlik doğrulama
- `X-Device-Id: <uuid>` → Hangi cihazdan geldiği
- `X-User-Name: <base64>` → Türkçe karakter güvenliği için Base64

Timeout: 30 saniye (görsel yükleme: 45 saniye)

### WebSocket Katmanı

`GET /api/ws?api_key=<key>` ile bağlanılır. Ping/pong 15 saniyede bir. Bağlantı kopunca 5 saniyede otomatik reconnect.

**WS üzerinden gelen event'ler:**

| Event | Tetikleyen | Yapılan |
|---|---|---|
| `cart_transfer_request` | Başka terminal sepet gönderdi | Dialog aç: kabul et / reddet |
| `cart_transfer_status_changed` | Transfer durumu değişti | UI güncelle |
| `cart_transfer_response` | Kabul/ret yanıtı geldi | Sepeti boş sekmeye aktar veya bildirim |
| `DEVICE_REJECTED` | Admin cihazı reddetti | Otomatik logout + disconnect |

---

## Cihaz Eşleştirme (Pairing) Sistemi — Adım Adım

Bir Flutter uygulaması ilk kez sunucuya bağlandığında şu akış işler:

```
App                          Server                     Admin
 │                              │                          │
 │── POST /api/pair/request ──► │                          │
 │   {device_id, name, type}    │                          │
 │                              │─ DB: status='pending' ──►│
 │◄── {status: 'pending'} ──────│                          │
 │                              │                          │
 │─── polling her 3 sn ────────►│                          │
 │    GET /api/pair/status/...  │                          │
 │                              │◄── POST /api/pair/approve─│
 │                              │    (admin onayladı)       │
 │◄── {status:'approved',       │                          │
 │     api_key:'inv_...'} ──────│                          │
 │                              │                          │
 │── api_key'i kaydet ──────────┘                          │
 │── LoginScreen'e geç                                     │
```

1. UUID `device_id` uygulama ilk açıldığında üretilir, global DB'ye kaydedilir (kalıcı)
2. Sunucu `pending` olarak `paired_devices` tablosuna yazar
3. Admin `/admin/devices` sayfasından veya `POST /api/pair/approve` ile onaylar
4. Onay yanıtında dönen `api_key` artık tüm sonraki isteklerde kullanılır
5. Sunucu ayrıca WebSocket üzerinden `DEVICE_REJECTED` yayınlayabilir → anlık logout

---

## Flutter App — Ekranlar ve Özellikler

### Navigasyon

`MainDashboard` sol menüsüyle yönetilen tek sayfa uygulaması:

```
MainDashboard
├── POS Ekranı         ← Varsayılan açılış
├── Ürünler
├── Analitik           ← Dashboard + Raporlar + Satış Geçmişi
├── Müşteriler & Tedarikçiler
├── Kasa (Vardiya)
├── Etiket Tasarımcısı
├── Ayarlar
└── Loglar
```

### POS Ekranı

En kritik ekran. 5 paralel sepet sekmesi destekler (aynı anda 5 farklı müşteri):

- Ürün arama (barkod + isim + keyword)
- `is_fast_product` işaretli ürünler hızlı erişim grid'inde
- Sepet öğesi başına birim indirim
- Tüm sepete yüzde veya sabit TL indirim
- Ödeme: Nakit / Kart / Veresiye / Karma (nakit+kart)
- Para üstü hesaplama
- Satış tamamlanınca `POST /api/sales` → sunucu stok düşer + `sale_items` kaydeder
- Sepet transfer: Başka bir terminale sepeti gönder (WebSocket üzerinden)

### Ürün Yönetimi

- Ürün ekle/düzenle/sil
- 3 farklı satış fiyatı (toptan, perakende, özel)
- Birim (kg, adet, lt, mt, koli vb.)
- Görsel yükleme (base64 → server `data/images/` klasörüne kaydedilir)
- Toplu işlemler: stok düzelt, fiyat güncelle, sil, Excel import/export
- Kritik stok uyarısı seviyesi
- Barkod desteği (harici okuyucu veya kamera)

### Analitik & Raporlar

- **Bugünkü özet**: Toplam ciro, işlem sayısı, ödeme tipi dağılımı, son 50 satış
- **Dönemsel rapor**: Günlük/Haftalık/Aylık/Yıllık → satış grafiği, en çok satan ürünler, kategori bazlı kırılım
- **Satış geçmişi**: Tarih filtrelemeli tam liste, satış kalemlerine drill-down

### Müşteri & Tedarikçi / Cari Hesap

- Müşteri ve tedarikçi kayıt yönetimi
- Vergi kimliği (vergi dairesi + numarası)
- Cari hesap: Borç/Alacak işlemleri (nakit, kart, veresiye ödeme)
- Bakiye takibi

### Vardiya Yönetimi

- Vardiya aç: Açılış kasası gir
- Vardiya kapat: Beklenen vs gerçek kapanış karşılaştırması
- Tüm vardiyaların geçmişi

### Etiket Tasarımcısı

- Sürükle-bırak bileşenli etiket tasarımı
- Barkod, QR kod, fiyat, ürün adı gibi alanlar
- Şablon kaydetme/yükleme (sunucuya sync'lenir)
- PDF ve termal yazıcı çıktısı

### Ayarlar (4 Sekme)

- **Uygulama**: Tema (açık/koyu), sesler, bildirimler
- **İşletme**: İşletme adı, KDV oranı, termal yazıcı genişliği
- **Kullanıcılar**: Personel yönetimi (yeni ekle, şifre değiştir, rol ata)
- **Senkronizasyon**: Sunucu bağlantısı, cihaz bilgisi, veri sıfırlama

---

## Senkronizasyon Stratejisi (3 Katmanlı Cache)

App her veri çekme isteğinde önce staleness kontrol eder:

```
1. GET /api/check-update?table=products
   → server: {count: 150, last_updated: "2026-06-05T10:30:00Z"}

   ↓ Lokal count ve tarih eşleşiyorsa:
   → Direk lokal cache döndür (ağ isteği YOK, ~0.1ms)

   ↓ Count aynı ama tarih farklıysa (kayıt güncellendi):
   → GET /api/products?since=<localLastUpdate>
   → Sadece değişen kayıtlar gelir → upsert

   ↓ Count farklıysa (ekleme/silme oldu):
   → GET /api/products (tam liste)
   → Lokal cache sıfırla, yeniden doldur
```

**Offline modu**: Sunucuya erişilemezse tüm işlemler lokal SQLite cache'den çalışır. Satış yapılabilir, raporlar gösterilebilir (son cache'lenmiş verilerle). Rapor cache'i settings tablosunda JSON olarak saklanır, staleness metadata ile yönetilir.

---

## Web Admin Paneli

Sunucu içinde tamamen Dart ile render edilen server-side HTML arayüz. Harici JS/CSS framework kullanılmaz.

**Session sistemi**: Cookie-based (24 saat), güvenli 32-byte random session ID. Sadece `owner` veya `manager` rolü erişebilir.

**Sayfalar:**

| Sayfa | İşlev |
|---|---|
| `/admin/dashboard` | Çalışma süresi, bugünkü ciro, ürün sayısı, bağlı cihaz sayısı, API key, versiyon |
| `/admin/devices` | Bekleyen eşleme isteklerini onayla/reddet; onaylı cihaz listesi, yeniden adlandırma, cihaz kaldırma |
| `/admin/users` | Personel ekleme/düzenleme/silme (staff_id, şifre, ad, rol, 9'lu izin checkbox grid — uygulama içiyle aynı granülerlik) |
| `/admin/roles` | Rol tanımlama/düzenleme/silme, izin checkbox grid |
| `/admin/settings` | İşletme bilgileri, KDV varsayılanı, termal genişlik, güncelleme kontrolü (`min_app_version`) |

UI: Dark theme, CSS variables, responsive grid — tamamen Dart string interpolation ile render edilir.

---

## Güvenlik Mimarisi

| Konu | Uygulama |
|---|---|
| Şifre saklama | SHA-256 hash, düz metin hiç saklanmaz veya iletilmez |
| API kimlik doğrulama | Cihaz bazında api_key (her terminal ayrı, bağımsız iptal edilebilir) |
| Path traversal koruması | Görsel upload'da `..`, `/`, `\`, null-byte kontrolü |
| SQL injection koruması | Ürün güncelleme `validCols` whitelist ile |
| Brute force koruması | Login: IP başına 10 başarısız denemede 5 dakika lockout |
| Admin session | Cookie `HttpOnly; SameSite=Strict`, 24 saat TTL |
| Ağ modu | Sunucu `0.0.0.0` (tüm ağ) veya `127.0.0.1` (sadece yerel) modunda çalıştırılabilir |

---

## Yardımcı Servisler

| Servis | İşlevi |
|---|---|
| `AutoBackupService` | Excel (.xlsx) ve JSON formatında otomatik yedekleme, `Documents/InventraPOS/` klasörüne |
| `CartTransferService` | WS üzerinden sepet transferi; dialog, kabul/ret, boş sekmeye aktarma |
| `SoundService` | Başarı, hata ve bildirim sesleri |
| `VersionCheckService` | `GET /api/version` ile `min_app_version` uyum kontrolü (ayar web admin panelinden `/admin/settings` üzerinden yönetilir, v0.1.5 ve öncesi cihazlarda bu kontrol koşamaz — manuel güncelleme gerekir) |
| `PdfService` | Satış fişi PDF oluşturma |
| `ReceiptPrinterService` | Termal yazıcı ESC/POS komutları |
| `ExcelService` | Ürün listesi ve satış verilerini Excel'e aktarma |

---

## State Yönetimi (Riverpod)

| Provider | İçeriği |
|---|---|
| `syncProvider` | Sunucu bağlantı durumu, pairStatus, serverUrl, isOnline |
| `authProvider` | Giriş yapmış kullanıcı, isLoading, error |
| `productProvider` | Ürün listesi (AsyncValue + cache katmanı) |
| `cartProvider` | 5 sekmeli sepet, miktarlar, indirimler, ödemeler |
| `analyticsProvider` | Günlük ciro özeti |
| `reportsProvider` | Dönemsel rapor verileri + chart data |
| `salesHistoryProvider` | Satış geçmişi + tarih filtresi |
| `cashProvider` | Aktif vardiya + vardiya geçmişi |
| `customerProvider` | Müşteri listesi |
| `supplierProvider` | Tedarikçi listesi |
| `clientTransactionProvider` | Cari işlem listesi |
| `webSocketProvider` | WS bağlantısı + event stream |
| `themeProvider` | Açık/koyu tema |

---

## Uygulama Akışı (Yeni Cihaz → Satış)

```
1. App başlar → AppGate (global DB kontrol)
   │
   ├─ serverUrl yok → ServerConnectScreen
   │   ├─ IP:Port gir → POST /api/pair/request
   │   ├─ Polling (3sn) → GET /api/pair/status
   │   └─ Admin onaylar → api_key alındı → global DB'ye kaydet
   │
   ├─ pairStatus != 'approved' → ServerConnectScreen (bekleme)
   │
   └─ pairStatus == 'approved' → LoginScreen
       ├─ staff_id + şifre gir → POST /api/auth/login
       └─ Başarılı → MainDashboard
           │
           ├─ İlk sync: GET /api/sync/snapshot (tam veri)
           │   → Tüm ürünler, ayarlar, kullanıcılar lokal cache'e yazılır
           │
           ├─ POS Ekranı açık
           │   ├─ Ürün seç → Sepete ekle
           │   ├─ Ödeme al → POST /api/sales → stok düşer
           │   └─ WebSocket açık → anlık bildirimler
           │
           └─ Sonraki açılışlarda: cache-hit → anlık, delta → fark al
```

---

## Özet

Inventra, **küçük ve orta ölçekli işletmeler için offline-first bir LAN POS sistemidir**. Sunucu Windows veya Linux'ta (ya da VDS'de) çalışır; kasiyerler Flutter uygulamasıyla Windows masaüstü veya Android tabletten bağlanır. İnternet kesintisinde bile çalışmaya devam eder. Çoklu terminal desteği var — bir işletmede aynı anda birden fazla kasa aynı sunucuya bağlanabilir. Güvenlik cihaz bazında api_key sistemiyle sağlanır, her terminali bağımsız olarak kaldırabilirsiniz. Web admin paneli üzerinden cihaz yönetimi, kullanıcı ve rol yönetimi, genel ayarlar yönetilebilir.

---

*Inventra POS — [github.com/iwhimss/inventra](https://github.com/iwhimss/inventra)*  
*Oluşturulma: 2026-06-05*

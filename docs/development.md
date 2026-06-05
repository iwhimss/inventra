# Inventra — Geliştirici Kurulum Kılavuzu

Bu kılavuz, Inventra POS projesini geliştirme ortamında çalıştırmak için gereken adımları kapsar.

---

## Gereksinimler

| Araç | Minimum | Kurulum |
|------|---------|---------|
| Dart SDK | 3.0+ | https://dart.dev/get-dart |
| Flutter SDK | 3.x | https://flutter.dev/docs/get-started/install |
| Git | herhangi | https://git-scm.com |
| Windows | 10/11 | (birincil platform) |

> **Not:** Flutter, Dart SDK'yı kendi içinde barındırır. `flutter doctor` çalıştırarak her iki SDK'nın da kurulu olup olmadığını doğrulayabilirsiniz.

---

## Projeyi Klonla

```bash
git clone https://github.com/iwhimss/inventra.git
cd inventra
```

Proje iki alt proje içerir:

```
inventra/
├── inventra_server/   ← Dart HTTP sunucu (önce bu çalışmalı)
└── inventra_app/      ← Flutter masaüstü uygulaması
```

---

## 1. Sunucuyu Çalıştır (`inventra_server`)

### Bağımlılıkları yükle

```bash
cd inventra_server
dart pub get
```

### İlk kurulum (yalnızca bir kez)

```bash
dart run bin/server.dart --setup
```

Setup wizard sırasıyla şunları sorar:

```
İşletme Adı: Örnek Market
Yönetici Staff ID [1000]: 1000
Yönetici Şifre: ••••••••
Şifre Tekrar: ••••••••
Port [5000]: 5000
Ağ erişimi [0=Sadece bu cihaz / 1=Tüm ağ] [varsayılan: 1]: 0
```

> **Geliştirmede `0` (127.0.0.1) seçin** — sunucu yalnızca kendi makinenizden erişilebilir olur.  
> Flutter uygulaması aynı makinede çalışacağından bu yeterlidir.

Kurulum tamamlandığında `data/` klasörü oluşur:

```
inventra_server/
└── data/
    ├── config.json    ← Sunucu ayarları (port, api_key, vb.)
    └── inventra.db    ← SQLite veritabanı
```

### Sunucuyu başlat

```bash
dart run bin/server.dart
```

Başarılı çıktı:

```
  📂 Data dizini : D:\...\inventra_server\data
  🏪 İşletme     : Örnek Market
  🌐 Adres       : 127.0.0.1:5000

Inventra Server çalışıyor → http://127.0.0.1:5000
Çıkmak için Ctrl+C basın.
```

### Bağlantıyı doğrula

Tarayıcıda veya terminalde:
```bash
curl http://127.0.0.1:5000/health
# {"status":"ok","uptime_seconds":12}
```

Admin paneli: http://127.0.0.1:5000/admin  
(Staff ID ve setup sırasında belirlediğiniz şifre ile giriş yapın)

---

## 2. Uygulamayı Çalıştır (`inventra_app`)

> Sunucunun çalışıyor olması **gerekmez** — uygulama sunucuya bağlanamadığında offline modda başlar. Ancak sunucu bağlantısı test etmek istiyorsanız önce sunucuyu başlatın.

Yeni bir terminal açın:

```bash
cd inventra_app
flutter pub get
flutter run -d windows
```

İlk çalıştırma `Sunucu Bağlantısı` ekranında açılır. Sunucu adresini girin:

```
127.0.0.1:5000
```

`Bağlan` tuşuna basın. Sunucu eşleme isteğini otomatik olarak admin panelinden onaylamanız gerekir:

→ http://127.0.0.1:5000/admin → **Cihazlar** → Bekleyen isteği **Onayla**

Onay sonrası uygulama giriş ekranına geçer.

---

## Tipik Geliştirme Akışı

```
Terminal 1 (sunucu):           Terminal 2 (uygulama):
─────────────────────          ──────────────────────────
cd inventra_server             cd inventra_app
dart run bin/server.dart       flutter run -d windows
        ↓                              ↓
  [sunucu çalışıyor]           [uygulama açılıyor]
        ↓                              ↓
  [değişiklik yap]             [hot reload: r tuşu]
  [Ctrl+C → tekrar başlat]     [hot restart: R tuşu]
```

> **Sunucu hot reload desteklemez.** Dart kaynak dosyasında değişiklik yaptıktan sonra Ctrl+C ile durdurup `dart run bin/server.dart` ile yeniden başlatın.

---

## Sık Kullanılan Komutlar

### Sunucu

| Komut | Açıklama |
|-------|----------|
| `dart run bin/server.dart` | Sunucuyu başlat |
| `dart run bin/server.dart --setup` | Kurulum wizard'ı (config + DB yoksa) |
| `dart run bin/server.dart --reset` | ⚠️ Tüm verileri sil, sıfırdan kur |
| `dart run bin/server.dart --local` | Sadece localhost (127.0.0.1) |
| `dart run bin/server.dart --port 8080` | Farklı port ile başlat |
| `dart run bin/server.dart --help` | Tüm seçenekleri listele |

### Uygulama

| Komut | Açıklama |
|-------|----------|
| `flutter run -d windows` | Windows uygulamasını başlat |
| `flutter run -d windows --release` | Release modda çalıştır |
| `flutter pub get` | Bağımlılıkları yükle/güncelle |
| `flutter analyze` | Statik analiz |
| `flutter clean` | Build cache temizle |

---

## Admin Paneli (Web Dashboard)

Sunucu çalışırken tarayıcıdan erişin: http://127.0.0.1:5000/admin

| Sayfa | URL | Açıklama |
|-------|-----|----------|
| Dashboard | `/admin/dashboard` | İstatistikler, stok uyarıları, 7 günlük satışlar |
| Ürünler | `/admin/products` | Stok ve fiyat düzenleme, arama |
| Satışlar | `/admin/sales` | Satış geçmişi, dönem filtresi |
| Loglar | `/admin/logs` | Aktivite logları |
| Cihazlar | `/admin/devices` | Eşleme isteklerini onayla/reddet |
| Kullanıcılar | `/admin/users` | Kullanıcı yönetimi |
| Ayarlar | `/admin/settings` | İşletme bilgileri, port/host, API key, sıfırlama |

---

## Sunucuyu Sıfırlama

Test sırasında temiz bir başlangıç yapmak için:

```bash
# Tüm verileri sil ve yeniden kurulum yap
dart run bin/server.dart --reset
```

Onay sorusu gelir:
```
⚠  UYARI: Bu işlem TÜM verilerinizi kalıcı olarak siler!
   Silinecekler: config.json, inventra.db, tüm resimler ve loglar

Devam etmek istediğinizden emin misiniz? [e/H]: e
```

Ardından setup wizard tekrar çalışır.

---

## Sunucu Ayarlarını Değiştirme

### A) Admin panelinden (önerilen)

1. http://127.0.0.1:5000/admin → **Ayarlar**
2. **Sunucu Yapılandırması** bölümünden port ve host'u düzenle
3. Kaydet → sunucuyu yeniden başlat

### B) CLI ile (tek seferlik geçersiz kılma)

```bash
# Farklı port ile başlat (config.json değişmez)
dart run bin/server.dart --port 8080

# Sadece localhost (config.json değişmez)
dart run bin/server.dart --local
```

### C) config.json'ı doğrudan düzenle

```
inventra_server/data/config.json
```

Değişiklikler sunucuyu yeniden başlatınca geçerli olur.

---

## Uygulama İkonu Güncelleme

`inventra_app/assets/icons/app_icon.png` dosyasını değiştirdikten sonra:

```bash
cd inventra_app
dart run flutter_launcher_icons
```

Bu komut Windows `.ico` ve Android `mipmap` ikonlarını otomatik olarak yeniden oluşturur.

---

## Sorun Giderme

### "Kurulum bulunamadı" hatası

```
⚠  Kurulum bulunamadı. Sunucuyu ilk kez çalıştırıyorsanız kurulumu başlatın:
   dart run bin/server.dart --setup
```

**Neden:** `data/config.json` yok. `--setup` çalıştırın.

---

### Sunucu başlıyor ama uygulama bağlanamıyor

1. Sunucunun `127.0.0.1:5000` adresinde dinleyip dinlemediğini kontrol edin:
   ```bash
   curl http://127.0.0.1:5000/health
   ```
2. Uygulamada girilen adresi kontrol edin: `127.0.0.1:5000` (http:// öneki olmadan)
3. Eşleme isteğini admin panelinden onaylamayı unutmayın.

---

### Flutter "windows" hedefi çalışmıyor

```bash
flutter doctor
flutter config --enable-windows-desktop
```

---

### `dart pub get` başarısız oluyor

```bash
dart pub cache repair
dart pub get
```

---

*Inventra POS v0.1.0 — [github.com/iwhimss/inventra](https://github.com/iwhimss/inventra)*

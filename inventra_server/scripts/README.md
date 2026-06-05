# Inventra Server — Scripts

Windows servis yönetimi için PowerShell scriptleri.

## Gereksinim: NSSM

NSSM (Non-Sucking Service Manager), herhangi bir uygulamayı Windows servisi olarak kayıt etmenizi sağlar.

**İndirme:** https://nssm.cc/download

İndirdikten sonra `nssm.exe`'yi şu konuma koyun:
```
inventra_server/scripts/nssm.exe
```

Veya PATH'te olan herhangi bir dizine koyun (`C:\Windows\System32\` vb.)

Chocolatey ile: `choco install nssm`

---

## Hızlı Başlangıç

Tüm komutları `inventra_server/` dizininden yönetici PowerShell'de çalıştırın.

### 1. Derle

```powershell
.\scripts\build.ps1
```

`build/inventra_server.exe` oluşturur.

### 2. Servisi Kur

```powershell
.\scripts\install-service.ps1
```

- NSSM ile `InventraServer` Windows servisi kaydeder
- Otomatik başlatma olarak ayarlar
- Logları `build/logs/stdout.log` ve `build/logs/stderr.log`'a yazar
- Crash sonrası 5 saniyede yeniden başlatır

### 3. Logları İzle

```powershell
.\scripts\view-logs.ps1          # stdout (normal loglar)
.\scripts\view-logs.ps1 -StdErr  # stderr (hata logları)
```

### 4. Durum Kontrol

```powershell
.\scripts\service-status.ps1
```

### 5. Servisi Kaldır

```powershell
.\scripts\uninstall-service.ps1
```

---

## Script Listesi

| Script | Açıklama |
|--------|----------|
| `build.ps1` | Dart projesini `.exe`'ye derler |
| `install-service.ps1` | NSSM ile Windows servisi kurar |
| `uninstall-service.ps1` | Servisi kaldırır |
| `view-logs.ps1` | Canlı log akışı gösterir |
| `service-status.ps1` | Servis ve port durumunu gösterir |

---

## Notlar

- Script'leri çalıştırmadan önce PowerShell execution policy ayarlayın:
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  ```
- `install-service.ps1` ve `uninstall-service.ps1` **yönetici** yetkisi gerektirir.
- `build/data/` dizini servisi kurulduktan sonra otomatik oluşur. Setup için `build\inventra_server.exe --setup` çalıştırın.

# Release Süreci — GitHub Releases Asset Adlandırma

Uygulama, sunucudaki `min_app_version` ayarına karşılık gelen GitHub Release'i
`GET https://api.github.com/repos/iwhimss/inventra/releases/tags/v{sürüm}`
üzerinden çeker, platforma uygun asset'i indirir
(bkz. `inventra_app/lib/core/services/version_check_service.dart`). Kurulum
otomatik başlatılmaz; kullanıcı indirilen dosyayı kendisi açar.

## Kesin adlandırma kuralı

Her release **tam olarak** aşağıdaki formatta oluşturulmalıdır (`min_app_version`
sunucuda `v` önekisiz, örn. `0.2.0` olarak tutulur; tag'e uygulama tarafında
otomatik `v` eklenir):

| Alan | Değer |
|------|-------|
| Release başlığı | `v{sürüm}` (örn. `v0.2.0`) |
| Tag | `v{sürüm}` (örn. `v0.2.0`) |
| Android asset dosya adı | `inventra-v{sürüm}.apk` (örn. `inventra-v0.2.0.apk`) |
| Windows asset dosya adı | `v{sürüm}-Windows.rar` (örn. `v0.2.0-Windows.rar`) |

Uygulama önce bu **tam** dosya adlarıyla eşleşme arar (büyük/küçük harf
duyarsız). Tam eşleşme bulunamazsa gevşek bir sezgisel kurala düşer (Android:
`.apk` ile biten ilk dosya; Windows: `.exe`/`.zip`/`.rar` ile biten veya
adında "windows" geçen ilk dosya) — bu, adlandırma kuralına tam uyulmayan
release'lerde de bir şeyler bulunabilmesi için bir güvenlik ağıdır, birincil
yöntem değildir.

## Bulunamama durumu

- İlgili tag'de release yoksa (GitHub 404 döner): "Güncelleme Bulunamadı"
  dialogu gösterilir, kullanıcı isterse Releases sayfasını manuel açabilir.
- Release var ama uygun asset yoksa: aynı dialog, farklı mesajla gösterilir.

Bu turda bir CI/CD otomasyonu (GitHub Actions ile otomatik derleme/yükleme)
**kurulmadı** — release'lerin her sürümde elle, yukarıdaki kurala tam uyularak
oluşturulup asset'lerin yüklenmesi gerekiyor.

# Release Süreci — GitHub Releases Asset Adlandırma

v0.2.0'dan itibaren uygulama, GitHub Releases API'sinden (`/repos/iwhimss/inventra/releases/latest`)
en son sürümü çekip, platforma uygun bir dosya varsa otomatik olarak indirir
(bkz. `inventra_app/lib/core/services/version_check_service.dart`). Kurulum
otomatik başlatılmaz; kullanıcı indirilen dosyayı kendisi açar.

Bu özelliğin çalışabilmesi için her GitHub Release'e **isminde belirli bir
uzantı/anahtar kelime geçen** bir dosya (asset) elle yüklenmelidir:

| Platform | Eşleşme kuralı | Örnek dosya adı |
|----------|----------------|------------------|
| Android  | Dosya adı `.apk` ile bitmeli | `inventra_app-android.apk` |
| Windows  | Dosya adı `.exe`/`.zip` ile bitmeli veya adında `windows` geçmeli | `inventra_app-windows.zip` |

Bir release'te bu kurallara uyan bir dosya bulunamazsa, uygulama otomatik
indirmeyi atlar ve eski davranışa döner: tarayıcıda
`https://github.com/iwhimss/inventra/releases/latest` sayfasını açar.

Bu turda bir CI/CD otomasyonu (GitHub Actions ile otomatik derleme/yükleme)
**kurulmadı** — release asset'lerinin her sürümde elle derlenip yüklenmesi
gerekiyor.

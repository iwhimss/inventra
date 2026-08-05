# Android Release İmzalama (kalıcı keystore kurulumu)

## Neden gerekli?

Android, bir uygulamayı güncellerken yeni APK'nın telefonda kurulu olan sürümle **aynı imza anahtarıyla** imzalanmış olmasını zorunlu kılar — farklıysa "Uygulama yüklenmedi" hatasıyla kurulumu reddeder.

Bu proje şu ana kadar Flutter'ın hazır şablonundaki **geçici** ayarı kullanıyordu: release APK'lar "debug" anahtarıyla imzalanıyordu (`android/app/build.gradle.kts` içinde `// TODO: Add your own signing config` notuyla işaretliydi). Debug anahtarı bilgisayara/ortama bağlı olduğu için, farklı bir zamanda/ortamda alınan bir build farklı bir imzayla çıkabilir — tam olarak yaşadığınız sorunun kaynağı bu.

`build.gradle.kts` artık `android/key.properties` dosyası varsa ondan okunan **kalıcı bir release keystore**'u otomatik kullanacak şekilde güncellendi. Dosya yoksa eski (debug) davranışa sessizce geri düşer — yani bu adımları yapana kadar hiçbir şey bozulmaz.

## Kurulum (bir kere yapılır, sonra hep aynı keystore kullanılır)

### 1. Keystore oluşturun

PowerShell'de (`inventra_app/android` klasöründe):

```bash
keytool -genkeypair -v -keystore inventra-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias inventra
```

Sorulan bilgileri doldurun (ad, organizasyon vb. — gerçek olması şart değil) ve **iki şifre** belirlemeniz istenecek (keystore şifresi ve anahtar şifresi — aynı da olabilirler). **Bu şifreleri ve oluşan `inventra-release-key.jks` dosyasını güvenli bir yere yedekleyin** — kaybederseniz bir daha bu anahtarla imzalayamazsınız ve uygulamanın gelecekteki güncellemelerini mevcut kurulumların üzerine yükleyemezsiniz.

`.jks` dosyası `inventra_app/android/` klasörüne kaydedilir — bu, repoya dahil edilmeyen (`.gitignore`'da zaten hariç) bir konumdur.

### 2. `key.properties` dosyasını oluşturun

`inventra_app/android/key.properties.example` dosyasını `inventra_app/android/key.properties` olarak kopyalayıp şifrelerinizi girin:

```
storePassword=<keystore şifreniz>
keyPassword=<anahtar şifreniz>
keyAlias=inventra
storeFile=../inventra-release-key.jks
```

Bu dosya da `.gitignore`'da hariç tutulmuştur, GitHub'a yüklenmez.

### 3. Build alın

```bash
flutter build apk --release
```

Artık APK, `key.properties`'teki kalıcı keystore ile imzalanacak.

## ⚠️ Önemli: Geçiş sırasında tek seferlik bir adım

Telefonunuzda hâlâ eski (debug-imzalı) sürüm kuruluyken, yeni (release-keystore-imzalı) bir APK'yı kurmaya çalışırsanız Android yine "Uygulama yüklenmedi" der — çünkü imzalar birbirinden farklı, bu beklenen bir durum. **Bu geçişte bir kereliğine**, telefondan eski Inventra uygulamasını kaldırıp yeni APK'yı öyle kurmanız gerekiyor. Bu adımdan sonra, aynı keystore'u kullanmaya devam ettiğiniz sürece güncellemeler sorunsuz üzerine yüklenecek.

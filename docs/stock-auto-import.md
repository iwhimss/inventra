# Otomatik Stok İçe Aktarma (SahraSoft vb.)

Başka bir programda (ör. SahraSoft) yönetilen ürün/stok verisini elle Excel'e aktarıp Inventra'ya yükleme zahmetini ortadan kaldırmak için: bir CSV dosyasını periyodik olarak izleyip, değiştiğinde otomatik olarak Inventra'ya aktaran bir özellik.

## Nasıl Çalışır?

Bu özellik, sunucuda değil **Inventra masaüstü uygulamasında** çalışır — çünkü izlenecek CSV dosyası genellikle mağazanızdaki bilgisayarın yerel diskinde bulunur (harici bir görev zamanlayıcısı tarafından periyodik olarak güncellenir), sunucunuz uzak bir VDS'te çalışıyorsa bu dosyaya erişemez.

1. Harici programınız (SahraSoft vb.) stok listesini bir CSV dosyasına dışa aktarır — siz bunu Windows Görev Zamanlayıcısı gibi bir araçla otomatikleştirebilirsiniz (örn. her 5 dakikada bir).
2. Inventra, bu dosyayı **Ayarlar → Uygulama** sayfasında belirttiğiniz aralıkla (varsayılan 5 dakika) kontrol eder.
3. Dosyanın son değiştirilme zamanı bir önceki kontrolden farklıysa, dosya okunup sütun eşleştirmenize göre ürünlere çevrilir ve **barkoda göre** ekle/güncelle olarak sisteme aktarılır (mevcut Excel içe aktarma ile aynı mantık: `/api/products/bulk-import`).
4. Değişmediyse hiçbir şey yapılmaz — gereksiz tekrar aktarım olmaz.

Bu özellik Inventra uygulamasının o bilgisayarda açık olmasını gerektirir (POS terminali olarak zaten gün boyu açık kalması beklenir).

## Kurulum

1. **Ayarlar → Uygulama** sayfasında "Otomatik Stok İçe Aktarma" bölümüne gidin.
2. **CSV Seç** ile izlenecek dosyayı seçin (örn. `stok.csv`).
3. Açılan **Sütun Eşleştirme** listesinde her Inventra alanının karşısına, CSV dosyanızdaki hangi sütuna karşılık geldiğini seçin. Bilinen SahraSoft başlıkları (`BARKOD`, `ADI`, `MIKTARI`, `ALIS`, `SATIS`, `KDV`, `MIKTARTÜRÜ`, `ALAN1`) otomatik olarak önerilir. Karşılığı olmayan alanları (Anahtar Kelimeler, Raf Konumu, Satış Fiyatı 2/3, Alternatif Barkodlar, Hızlı Ürün) **"Yok / Boş Bırak"** olarak bırakın — tıpkı Modüller → Dönüştürücü sayfasındaki gibi.
4. **Ürün Adı** ve **Satış Fiyatı** eşleştirmesi zorunludur.
5. **Etkin** anahtarını açın, kontrol sıklığını (dakika) isterseniz değiştirin.
6. **KAYDET**'e basın.

## Durum Takibi

Ayarlar sayfasındaki durum kartında şunları görürsünüz:
- Aktif/Pasif durumu
- Son kontrol zamanı
- Son içe aktarmada kaç ürün eklendiği/güncellendiği
- Varsa hata mesajı (örn. dosya bulunamadı)

Ayrıca **Stoklar** (Ürün Yönetimi) ve **Sepet** (POS) sayfalarının başlık alanında küçük bir rozet, en son senkronizasyonun ne zaman olduğunu özetler (özellik etkinken görünür).

## Sütun Referansı

| Inventra Alanı | Notlar |
|---|---|
| Barkod | Zorunlu değil ama boşsa satır sunucu tarafında atlanır (barkod eşleşmesiyle çalışıyor) |
| Ürün Adı | **Zorunlu** |
| Satış Fiyatı | **Zorunlu** |
| Stok Miktarı, Alış Fiyatı, KDV Oranı, Birim, Ürün Grubu | Opsiyonel, boşsa makul varsayılanlar kullanılır (KDV %20, Birim "Adet") |

Türkçe ondalık format (`"158,00"`) ve tırnaklı/virgüllü CSV alanları doğru şekilde ayrıştırılır.

## Sorun Giderme

- **"Sütun eşleştirmesi yapılmamış" hatası:** Ayarlar sayfasında dosyayı seçip en az Ürün Adı ve Satış Fiyatı eşleştirmesini yapıp kaydetmeniz gerekiyor.
- **"Dosya bulunamadı" hatası:** Seçtiğiniz dosya yolu değişmiş veya silinmiş olabilir — dosyayı tekrar seçin.
- Hiç değişiklik algılanmıyorsa, harici programınızın dosyayı gerçekten yeniden yazdığından (sadece açıp kapatmadığından) emin olun — kontrol, dosyanın "son değiştirilme zamanı"na bakarak yapılıyor.

# Fatura Eklentisi (Inventra Fatura Asistanı)

Inventra'nın **Modüller → Fatura Hazırlama** sayfasında hazırlanan ürün listesini, `turmobefatura.luca.com.tr` fatura oluşturma formuna otomatik dolduran bir Chrome/Brave (Chromium tabanlı) tarayıcı eklentisi.

Eklenti Chrome Web Store'a **yayınlanmıyor** — proje deposunda `inventra_invoice_extension/` klasörü olarak duruyor ve elle ("Developer Mode") yüklenir.

## Nasıl Çalışır?

Inventra masaüstü/mobil uygulaması bir web sayfası olmadığı için tarayıcı eklentisiyle doğrudan konuşamaz. Bunun yerine zaten çalışan `inventra_server`'ı köprü olarak kullanır:

1. Inventra'da "Fatura Hazırlama" sayfasında liste hazırlanır, **"EKLENTİYE AKTAR"** butonuna basılır → liste sunucuya gönderilir.
2. Tarayıcıda `turmobefatura.luca.com.tr` fatura oluşturma sayfası açıkken, eklentinin sağ üstte beliren panelinden **"Inventra'dan Doldur"** tıklanır → eklenti listeyi sunucudan çekip formu doldurmaya başlar.
3. Eklenti periyodik olarak sunucuya "heartbeat" gönderir; Inventra uygulaması bu sayede "Eklenti Bağlı ✓" / "Eklenti Bulunamadı" durumunu gösterebilir.

## Kurulum

1. `inventra_invoice_extension/` klasörünü bilgisayarınıza indirin (repo ile birlikte gelir, veya GitHub Release'den `inventra-v{sürüm}-invoicemodule.zip` indirip açın).
2. Brave/Chrome'da adres çubuğuna `chrome://extensions` yazın.
3. Sağ üstten **"Geliştirici modu"**nu (Developer mode) açın.
4. **"Paketlenmemiş öğe yükle"** (Load unpacked) butonuna basıp `inventra_invoice_extension/` klasörünü seçin.
5. Eklenti araç çubuğunda görünecek — ikonuna tıklayın.

## Sunucuyla Eşleştirme

1. Eklenti ikonuna tıklayınca açılan pencerede **Inventra Sunucu Adresi**ni girin (ör. `http://192.168.1.100:5000` veya VDS'inizin adresi).
2. **"Eşleştirme İste"** butonuna basın — tarayıcı sunucu adresine erişim izni isteyecek, onaylayın.
3. Inventra uygulamasını açıp **Ayarlar → Cihazlar** (veya sunucu admin panelindeki **Cihazlar** sayfası) üzerinden bekleyen isteği onaylayın — bu, mevcut POS cihaz eşleştirme sistemiyle birebir aynı akıştır.
4. Onaylandıktan birkaç saniye sonra eklenti penceresinde **"Bağlandı ✓"** görünecek.

## Kullanım

1. Inventra'da fatura listesini hazırlayıp **"EKLENTİYE AKTAR"**a basın (bu buton sadece eklenti bağlıyken aktiftir).
2. `turmobefatura.luca.com.tr` fatura oluşturma sayfasını açın.
3. Sağ üstte beliren Inventra panelinden **"Inventra'dan Doldur"**a basın.
4. Eklenti satırları sırayla doldururken panelde her satırın durumu görünür (✓ dolduruldu / ✗ eşleşmedi). İşlem sırasında **"Duraklat"** veya **"Durdur"** butonlarıyla süreci kontrol edebilirsiniz.
5. İşlem bitince panelde kaç satırın başarıyla dolduğu, kaç satırın eşleşmediği özetlenir — eşleşmeyen ürünleri elle tamamlamanız gerekir.

## Güncelleme

Chrome Web Store'da olmadığı için **otomatik güncelleme yoktur**. Yeni bir sürüm çıktığında:

1. Yeni `inventra_invoice_extension/` klasörünü (veya GitHub Release'deki güncel zip'i) indirip eski klasörün üzerine yazın.
2. `chrome://extensions` sayfasında eklentinin kartındaki **"Yenile"** (yenileme/refresh) ikonuna basın.

## Bilinen Sınırlamalar

- Eklentinin ürün eşleştirme mantığı, luca.com.tr'nin kendi ürün arama önerilerine (typeahead) dayanır — sitenin kendi kataloğunda olmayan bir ürün adı için öneri çıkmaz, o satır otomatik olarak "eşleşmedi" işaretlenip bir sonraki satıra geçilir.
- KDV oranı sitede sadece `0, 1, 8, 10, 18, 20` değerlerini kabul ediyor; ürününüzün KDV oranı bu listede yoksa en yakın değere yuvarlanır ve panelde uyarı olarak gösterilir.
- İlk sürümde (v0.2.3) bazı DOM seçicileri (özellikle 2. ve sonraki satırların alan id'leri, öneri listesinin CSS seçicisi) canlı sayfa üzerinde tam doğrulanamadan yazıldı — bazı satırlarda beklenmeyen davranış görülürse lütfen bildirin, bir sonraki sürümde düzeltilecektir.

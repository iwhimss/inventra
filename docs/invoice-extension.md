# Fatura Eklentisi (Inventra Fatura Asistanı)

Inventra'nın **Modüller → Fatura Hazırlama** sayfasında hazırlanan ürün listesini, `turmobefatura.luca.com.tr` fatura oluşturma formuna otomatik dolduran bir Chrome/Brave (Chromium tabanlı) tarayıcı eklentisi.

Eklenti Chrome Web Store'a **yayınlanmıyor** — proje deposunda `inventra_invoice_extension/` klasörü olarak duruyor ve elle ("Developer Mode") yüklenir.

## Nasıl Çalışır?

Inventra masaüstü/mobil uygulaması bir web sayfası olmadığı için tarayıcı eklentisiyle doğrudan konuşamaz. Bunun yerine zaten çalışan `inventra_server`'ı köprü olarak kullanır. Birden fazla tarayıcı/cihaza eklenti kurup eşleştirebilirsiniz — Inventra'da fatura hazırlarken hangisine göndereceğinizi seçersiniz.

1. Inventra'da "Fatura Hazırlama" sayfasında liste hazırlanır, hedef cihaz (eşleştirilmiş eklentilerden biri) seçilip **"EKLENTİYE AKTAR"** butonuna basılır → liste, seçilen cihaza özel olarak sunucuya gönderilir.
2. Tarayıcıda yeni bir liste geldiğinde eklenti bir **bildirim** gösterir. Araç çubuğundaki eklenti simgesine tıklayınca açılan popup'ta *"{kullanıcı adı} kullanıcısından N ürünlük liste geldi, kabul edilsin mi?"* sorusu çıkar.
3. **Kabul Et**'e basılınca liste sunucudan çekilir ve popup "Doldur" ilerleme ekranına geçer; `turmobefatura.luca.com.tr` fatura oluşturma sayfası o an açık ve aktifse doldurma otomatik başlar.
4. Eklenti periyodik olarak sunucuya "heartbeat" gönderir; Inventra uygulaması bu sayede her eşleştirilmiş cihazın bağlı olup olmadığını gösterebilir.

**Not:** Popup, hem fatura oluşturma (`/Invoice/Create`) hem de taslak/mevcut bir faturayı düzenleme (`/Invoice/Edit?InvoiceId=...`) sayfası aktif sekmedeyken doldurma kontrollerini gösterir — başka bir sayfadaysanız önce o sekmeye geçmeniz gerekir.

**Yeniden aktarım / güncelleme:** Aynı sayfada (ya da bir taslağı düzenlerken) daha önce doldurulmuş satırlar varsa, eklenti onları tekrar "Yeni Satır Ekle" ile çoğaltmaz — sayfada zaten kaç satır olduğunu tespit edip sadece gerçekten yeni eklediğiniz ürünler için yeni satır açar, mevcut satırları ise (miktar/fiyat değişikliği varsa dahil) üzerine yazarak günceller.

## Kurulum

1. `inventra_invoice_extension/` klasörünü bilgisayarınıza indirin (repo ile birlikte gelir, veya GitHub Release'den `inventra-v{sürüm}-invoicemodule.zip` indirip açın).
2. Brave/Chrome'da adres çubuğuna `chrome://extensions` yazın.
3. Sağ üstten **"Geliştirici modu"**nu (Developer mode) açın.
4. **"Paketlenmemiş öğe yükle"** (Load unpacked) butonuna basıp `inventra_invoice_extension/` klasörünü seçin.
5. Eklenti araç çubuğunda görünecek — ikonuna tıklayın.

## Sunucuyla Eşleştirme

1. Eklenti ikonuna sağ tıklayıp **"Seçenekler"** (veya popup'taki **"⚙ Ayarlar"** bağlantısı) ile Ayarlar sayfasını açın.
2. **Inventra Sunucu Adresi**ni girin — `http://` veya `https://` ile başlamalı (ör. `http://192.168.1.100:5000` yerel ağda, `https://...` VDS/domain kullanıyorsanız — sunucunuz hangisini destekliyorsa onu yazın, protokol otomatik tahmin edilmez).
3. **"Eşleştirme İste"** butonuna basın — tarayıcı sunucu adresine erişim izni isteyecek, onaylayın.
4. Inventra uygulamasını açıp **Ayarlar → Cihazlar** (veya sunucu admin panelindeki **Cihazlar** sayfası) üzerinden bekleyen isteği onaylayın — bu, mevcut POS cihaz eşleştirme sistemiyle birebir aynı akıştır. Cihaz listesinde eklenti "🧩 Tarayıcı Eklentisi" etiketiyle görünür.
5. Onay arkaplanda otomatik algılanır (en geç ~1 dakika içinde) — Ayarlar sayfasını açık tutmanıza gerek yoktur. Bağlandığında araç çubuğu simgesinde yeşil bir ✓ rozeti belirir.

Birden fazla tarayıcı/bilgisayara eklenti kurup ayrı ayrı eşleştirebilirsiniz; her biri Cihazlar listesinde ayrı bir isimle görünür ve Inventra'da fatura gönderirken hangisini hedefleyeceğinizi seçersiniz.

## Kullanım

1. Inventra'da fatura listesini hazırlayın, alttaki dropdown'dan **hedef cihazı** (hangi tarayıcıdaki eklentiye gönderileceğini) seçin, **"EKLENTİYE AKTAR"**a basın.
2. Tarayıcıda yeni liste geldiğinde bir bildirim belirir (isterseniz beklemeden de simgeye tıklayabilirsiniz).
3. Eklenti simgesine tıklayın — popup'ta gönderen kullanıcı ve ürün sayısıyla birlikte onay ekranı çıkar: **Kabul Et** veya **Reddet**.
4. **Kabul Et**'e bastığınızda, `turmobefatura.luca.com.tr` fatura oluşturma sayfası aktif sekmedeyse doldurma otomatik başlar — ürün adı da tıpkı Miktar/Birim Fiyat gibi serbest metin olarak yazılır (site tarafında ürün kataloğu kullanmıyorsanız hiçbir öneri listesi beklenmez), Birim ve KDV alanları ise dropdown olduğu için sitedeki seçeneklerle metin eşleştirilerek seçilir. Popup'ta her satırın durumu görünür (✓ dolduruldu, ⚠ uyarı var — üzerine gelince ne olduğu görünür, ✗ satır bulunamadı), **"Duraklat"** veya **"Durdur"** ile süreci kontrol edebilirsiniz.
5. Popup'ı kapatıp tekrar açsanız da (doldurma arkaplanda devam ettiği için) ilerlemeyi kaldığı yerden görürsünüz.
6. İşlem bitince kaç satırın başarıyla dolduğu, kaç satırın eşleşmediği özetlenir — eşleşmeyen ürünleri elle tamamlamanız gerekir.

## Güncelleme

Chrome Web Store'da olmadığı için **otomatik güncelleme yoktur**. Yeni bir sürüm çıktığında:

1. Yeni `inventra_invoice_extension/` klasörünü (veya GitHub Release'deki güncel zip'i) indirip eski klasörün üzerine yazın.
2. `chrome://extensions` sayfasında eklentinin kartındaki **"Yenile"** (yenileme/refresh) ikonuna basın.

## Sorun Giderme

- **"Sunucudan liste alınamadı: Failed to fetch"** hatası artık oluşmamalı — önceki sürümde bu hata, sunucuyla konuşan kodun fatura sayfasına enjekte edilen içerik betiğinde çalışmasından kaynaklanıyordu (sayfanın kendi güvenlik politikası dış isteği engelliyordu). Artık tüm sunucu iletişimi eklentinin arkaplan servisinde toplandığı için bu sınıf hata oluşmamalı. Yine de bir hata görürseniz popup'taki mesajı olduğu gibi bildirin.
- **"İzin isteği başarısız" / eşleştirme çalışmıyor:** adresin `http://` veya `https://` ile doğru başladığından emin olun (VDS/domain genelde `https://`, yerel ağ IP'si genelde `http://`).
- Popup "Sayfayla bağlantı kurulamadı" derse: sayfayı yenileyin (eklenti güncellendikten hemen sonra açık kalan sekmelerde içerik betiği yeniden yüklenmemiş olabilir).
- **Bir satır hiç dolmuyorsa veya bazı alanlar eksik kalıyorsa:** `turmobefatura.luca.com.tr` sekmesinde F12 → Console'u açıp `[Inventra]` ile başlayan satırlara bakın — hangi alanın hangi id ile arandığı ve bulunup bulunmadığı orada adım adım loglanır. Bu çıktıyı olduğu gibi paylaşmanız, sorunu DOM parçası istemeden hızlıca teşhis etmemizi sağlar.

## Bilinen Sınırlamalar

- Ürün Adı alanı, sitenin kendi ürün kataloğunu kullanıyorsanız normalde bir öneri/otomatik-tamamlama listesi gösterir — ama eklenti bu listeyi hiç beklemez veya tıklamaz, adı doğrudan serbest metin olarak yazar (kataloğa bağlı olmayan, elle giriş yapılan kullanım şekliyle uyumlu). Kataloğu aktif kullanıyorsanız ürünün otomatik seçilmesi gerekiyorsa bu, eklentinin şu anki kapsamı dışındadır.
- KDV oranı sitede sadece `0, 1, 8, 10, 18, 20` değerlerini kabul ediyor; ürününüzün KDV oranı bu listede yoksa en yakın değere yuvarlanır ve popup'ta uyarı olarak gösterilir.
- Satır indeksleme kuralı (`#Miktar1`, `#Miktar2`... — 2. ve sonraki satırların alan id'leri) canlı sayfada tam doğrulanmadan yazıldı; bir satır "bulunamadı" olarak işaretlenirse (özellikle 2+ satırlarda) yukarıdaki konsol log yöntemiyle bildirin.
- `/Invoice/Edit?InvoiceId=...` sayfasının DOM yapısının `/Invoice/Create` ile birebir aynı alan id'lerini kullandığı varsayılıyor (aynı site, aynı ürün satırı bileşeni) ama bu canlı olarak doğrulanmadı — sorun yaşarsanız konsol log'larını paylaşın.

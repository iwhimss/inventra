# Inventra - Çoklu Barkod (Alias Barkod) Sistemi

## Problem

SFS Elektrik dükkanında ürünler tedarikçiden kutu halinde geliyor (ör. Viko topraklı priz, kutuda 20 adet). Kutu içindeki ürünlerin barkodu aynı, ancak bir sonraki siparişte aynı ürün farklı bir barkodla gelebiliyor (tedarikçi kaynaklı). Bu yüzden:

- Yeni gelen ürün sistemde mevcut ürünle eşleşmiyor, sanki yeni bir ürünmüş gibi tekrar tekrar kayıt açılıyor.
- Kasada hızlı satış için ürünün üzerindeki orijinal barkod okutulabilmeli; manuel/özel barkod üretip ürüne yapıştırmak ~3000 SKU için sürdürülebilir değil.

## Çözüm: Bir Ürüne Birden Fazla Barkod Tanımlama (Alias Barcode)

Mevcut yapıdaki "1 ürün = 1 barkod" (genelde `products` tablosunda `barcode` kolonu) modelinden, "1 ürün = N barkod" modeline geçilecek.

### Veritabanı Şeması

**products** (mevcut tablo, değişmeden kalır, sadece `barcode` kolonu artık zorunlu/tekil olmaktan çıkar veya tamamen kaldırılır)
- id
- name
- ... (diğer mevcut alanlar)

**barcodes** (yeni tablo)
- id
- barcode_value (string, index'li ama UNIQUE DEĞİL — çünkü bir barkod birden fazla ürüne bağlanabilir, bkz. aşağıdaki "Barkod Çakışması" bölümü)
- created_at

**barcode_product_links** (yeni ara tablo - many-to-many)
- id
- barcode_id (FK -> barcodes.id)
- product_id (FK -> products.id)
- is_primary (boolean, opsiyonel: o ürün için "ana" barkod hangisi, raporlama/etiket basımında kullanılabilir)
- created_at
- UNIQUE constraint: (barcode_id, product_id) ikilisi tekrar edemez

Bu yapı sayesinde:
- Bir ürünün birden fazla barkodu olabilir (farklı parti/tedarikçi barkodları).
- Bir barkod, istisnai durumlarda birden fazla ürüne bağlı olabilir (bkz. aşağıda).

### Akış 1: Mal Kabulde Yeni/Bilinmeyen Barkod Okutulduğunda

1. Kullanıcı barkodu okutur.
2. Sistem `barcodes` tablosunda arar.
   - **Hiç kayıt yoksa:** "Bu barkod sistemde yok. Hangi ürüne ait?" diye ürün arama/seçme ekranı açılır. Seçim yapılınca `barcodes` + `barcode_product_links` kaydı oluşturulur.
   - **Kayıt var ve tek bir ürüne bağlıysa:** Direkt o ürün olarak işlem görür (stok girişi vs.).
   - **Kayıt var ve birden fazla ürüne bağlıysa:** Bkz. Akış 3 (kasa/seçim ekranı).

### Akış 2: Barkod Başka Bir Ürüne Zaten Kayıtlıyken Yeni Eşleştirme Yapılmak İstendiğinde

Senaryo: "Viko Tekli Topraklı Priz" için zaten kayıtlı bir barkod, yeni gelen "Viko İkili Topraklı Priz" kutusunda da okutuldu.

Sistem şu 3 seçeneği sunmalı:

1. **Taşı:** Bu barkod aslında yeni ürüne ait, eskisi hataydı → eski linki sil, yeni ürüne bağla.
2. **İkisine de bağla (paylaşılan barkod):** Nadir ama gerçek bir çakışma durumu (tedarikçi barkod standardına uymamış olabilir) → barkodu yeni ürüne de ekle, eski link kalır. Artık bu barkod 2 ürüne bağlı.
3. **İptal:** Hiçbir şey yapma, bu eşleştirmeyi ekleme.

### Akış 3: Kasada/Stokta Barkod Okutma (Satış veya Sayım Anında)

1. Barkod okutulur.
2. `barcode_product_links` tablosunda bu barkoda bağlı kaç ürün var bakılır.
   - **1 ürün:** Direkt o ürün ekranına/satışına geçilir (mevcut davranış, ekstra adım yok).
   - **Birden fazla ürün (paylaşılan barkod durumu):** Küçük bir seçim modalı açılır: "Bu barkod birden fazla ürüne kayıtlı: [Viko Tekli Topraklı Priz] / [Viko İkili Topraklı Priz] — hangisi?" Kullanıcı bir tık ile seçer, işlem devam eder.

Bu durum nadir olacağı için günlük kullanıma ek yük getirmez; sadece çakışma olduğunda bir ekstra tıklama ister.

## Özet - Neden Bu Yapı

- Tedarikçi barkodu değiştiğinde ürün kaybolmaz, yeni barkod kolayca mevcut ürüne eklenir.
- Kendi özel barkodu üretip 3000 ürüne tek tek yapıştırma ihtiyacı ortadan kalkar; ürünün üzerindeki orijinal tedarikçi barkodu kullanılabilir.
- Nadir barkod çakışmalarında sistem kilitlenmez, kullanıcıya seçim sunularak doğru ürün belirlenir.
- Veri bütünlüğü `UNIQUE(barcode_id, product_id)` kısıtı ile korunur; aynı barkod-ürün ikilisi tekrar kaydedilmez.

## Yapılacaklar (Claude Code için)

1. `barcodes` ve `barcode_product_links` tablolarını oluştur (migration).
2. Mevcut `products.barcode` verisini yeni tabloya taşıyan bir migration scripti yaz (her mevcut ürün-barkod çifti `barcode_product_links`'e aktarılacak).
3. Mal kabul ekranına "bilinmeyen barkod" ve "barkod başka ürüne kayıtlı" akışlarını ekle (Akış 1 ve 2).
4. Kasa/satış ekranındaki barkod okutma mantığını güncelle: birden fazla eşleşme varsa seçim modalı göster (Akış 3).
5. Ürün detay sayfasına "bu ürüne bağlı barkodlar" listesini ve barkod ekleme/silme arayüzünü ekle.

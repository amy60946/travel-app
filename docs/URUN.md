# TravelApp ürün belgesi

Son güncelleme: 2026-10-24. Bu dosya "Polarsteps ilhamı" ekranlarını ve
Polarsteps incelemesinin sonuçlarını tek referansta birleştirir; yazılım
bu belgeye göre yapılır. Okunabilir kopyası: Claude Docs'ta "TravelApp
ürün belgesi". Kararların asıl kaydı `CLAUDE.md` → Kararlar.

## Özet

TravelApp, Instagram, TikTok ve Google Maps'te kaydedilen yerleri harita
üstünde günlük yürüyüş rotasına çevirir ve yürürken rehber gibi sesli
anlatır.

- **Kimin için:** yurt dışından gelen turistler ve yurt içinde gezen
  yerli gezginler. İlk test şehri Tokyo, ilk test eden Oguz.
- **Polarsteps'ten alınanlar:** küre ana sayfa, harita üstte ve günler
  altta plan, "+" menüsü, "Planla / Yürü" geçişi, koleksiyon, kendi
  yerini oluşturma.
- **Fark:** Polarsteps'te yürürken sesli anlatım yok. Bizde her yerin
  "Dinle" kartı var; yere yaklaşınca anlatım kendiliğinden başlar.
- **Bütçe sıfır:** yalnızca ücretsiz servisler; tek istisna, yalnızca
  puan için Tripadvisor'ın ücretsiz katmanı (ayda 5.000 çağrı).

## Kullanıcı akışı

1. **Kaydet:** iOS paylaşma menüsü ya da "verilerini indir" dosyası. Yer
   kendiliğinden eklenir; emin değilse "Tahmini" etiketi, isterse
   "Değiştir".
2. **Küre:** açılışta kayıtlı şehirler fotoğraflı pin ("Tokyo · 24");
   altta Gezilerim / Kayıtlarım.
3. **Plan:** şehre dokununca harita üstte, günler altta; gün sayısı
   − / +, tempo seçimi; rota kendiliğinden hazırlanır.
4. **Ekle:** "+" menüsü: yer, kayıtlardan yer, kendi yeri, şehir. Gün
   kendiliğinden seçilir.
5. **İncele:** yer sayfası: fotoğraflar, puan, saatler, "Dinle", ipuçları.
6. **İndir:** harita ve anlatımlar yürüyüşten önce telefona iner.
7. **Yürü:** harita açık, altta küçük sesli çalar; yaklaşınca anlatım
   kendiliğinden başlar.

## Ekranlar

Esas akış `P-` ile başlayan ekranlar; Polarsteps'te karşılığı olmayan beş
ekran `N-` setinden. Dosyalar `design/ekranlar/`, tıklanabilir pano
linki `design/README.md`'de.

| # | Ekran | Ne yapar | Kurallar | Taslak |
|---|---|---|---|---|
| 1 | Ana sayfa (küre) | Kürede şehir pinleri; altta Gezilerim / Kayıtlarım; alt çubukta Keşfet, Kayıtlar, İndirilenler ve siyah "+" | Sıradaki gezi siyah pin, diğerleri beyaz; pin = fotoğraf + ad + yer sayısı | P-Ana |
| 2 | Kayıtlarım | Aktarılan yerler 2 sütun fotoğraf kartı; kaynağa göre süzme (Tümü / Instagram / TikTok / Google Maps); kartta "+" ile seç, "Rotaya ekle" | Gün kendiliğinden seçilir; kartta kaynak etiketi ve tür | P-Koleksiyon |
| 3 | Şehir planı | Harita üstte (gün numaralı pinler, gerçek sokaklardan rota), altta gün kartları; günler arası ulaşım süresi; − / + gün; "Planla / Yürü"; "+" menüsü | Menü: Yer ekle, Kayıtlarından ekle, Kendi yerini oluştur, Şehir ekle, Rotayı yeniden düzenle. Uçuş ve konaklama yok | P-Plan |
| 4 | Gün rotası | Bir günün durakları haritada; "Günü hafiflet", "Yürüyüşe başla"; harita türü (standart, uydu, karma) | Her işlemde "Geri al" | N-Rota |
| 5 | Yer ekle | Arama; Kendi yerini oluştur; Fotoğrafla ekle; "Kayıtlarından" ve "Popüler yerler", satırda "+" | Popüler yerler Wikipedia okunma sayısına göre; altta kaynaklar | P-YerEkle |
| 6 | Yer sayfası | Ad, bölge, tür; fotoğraflar; puan (Tripadvisor), açık/kapalı, ortalama süre; Dinle kartı; "Instagram'da kaydettin"; açıklama, ipuçları, bilgiler | Her metnin altında kaynağı; alt çubuk "Rotaya ekle" ya da "Rotada · Çıkar" | P-Yer |
| 7 | Kendi yerin | Fotoğraf, ad, adres + pin (sürüklenerek düzeltilir), tür, not, gün | Gün varsayılanı "Otomatik" (en yakın gün) | P-OzelYer |
| 8 | Yürü | Harita açık; üstte yön kartı; "Yaklaştın, anlatım başladı"; altta küçük çalar ve "Sıradaki" | Anlatımlar üst üste binmez; telefon cepteyken de çalışır | P-Yuruyus |
| 9 | Paylaş ile eklendi | "Tokyo'ya eklendi", "Geri al", "Yanlış yer mi? Değiştir" | Onay kartı yok; 3 saniyenin altı | N-Paylas |
| 10 | Fotoğrafla ekle | Tabela/bina çekilir, yer konumla bulunur | MVP (karar 2026-10-24); sormadan tahmin + "Değiştir" | N-Kamera |
| 11 | Veri aktar | Instagram, TikTok, Google Maps veri dosyası; kopyalanan linki algılama | Kazıma (scraping) yok | N-YerEkle |
| 12 | Gün ve tempo | Gün sayısı, tempo (Rahat 3-4, Normal 5-6, Tempolu 7+ durak), anlatım dili | "X yer sığar" anında güncellenir | N-Plan |
| 13 | İndirilenler | Harita, anlatım, yön sesleri indirme durumu; "Yalnızca Wi-Fi" | İnternetsiz yürüyüş için şart | N-Indir |

## Veri kaynakları

| Bilgi | Kaynak | Ücret | Kural |
|---|---|---|---|
| Harita, yer arama, adres, saatler, yaya yol tarifi | Apple Haritalar (MapKit) | iPhone uygulamasında ücretsiz | "Apple Haritalar" kaynağı gösterilir |
| Popüler yerler ve sırası | Wikipedia (sayfa okunma sayısı) | Ücretsiz | Kaynak gösterilir |
| Açıklama ve anlatım metni | Wikipedia | Ücretsiz | CC BY-SA: özetlenebilir, sesli okunabilir, kaynak gösterilir |
| İpuçları | Wikivoyage | Ücretsiz | CC BY-SA 4.0 |
| Yer türü, konum yedeği | OpenStreetMap, Foursquare açık yer verisi | Ücretsiz | Kaynak gösterilir |
| Kişisel yerler | Kullanıcının Instagram, TikTok, Google Maps kayıtları | Ücretsiz | Paylaşma menüsü ve veri dosyası; kazıma yok |
| Puan | Tripadvisor Content API | Ayda 5.000 çağrı ücretsiz; hesap için kredi kartı (Oguz açar) | Günlük sınır; yalnızca yer numarası saklanır; puan sesli okunmaz, değiştirilmez; logo ve puan görseli Tripadvisor'ın verdiği gibi |
| Ses | iPhone'un kendi sesi | Ücretsiz, internetsiz | Daha doğal ücretsiz ses sonra birlikte seçilir |

Tripadvisor koşulları içeriğinin başka kullanıcı içeriğiyle (ör.
Wikivoyage ipuçları) yan yana gösterilmesini kısıtlıyor; hesap açılınca
gösterim kuralları yeniden okunacak. API anahtarı yalnızca GitHub
Secrets'ta durur.

## Sesli rehber

1. **Metni topla:** yerin Wikipedia ve şehrin Wikivoyage sayfası
   (Tripadvisor metni kullanılmaz).
2. **Özetle:** ücretsiz bir yapay zekâ servisiyle 2-3 dakikalık rehber
   anlatımı; en az bir kaynakla çapraz kontrol; Türkçe ve İngilizce.
3. **Sakla:** her yer için bir kez üretilir, herkes aynısını kullanır.
4. **İndir:** harita, anlatım ve yön sesleri yürüyüşten önce iner.
5. **Seslendir:** iPhone'un sesi; yer adı okunuşları kontrol edilir.
6. **Çal:** yaklaşınca (ör. 40-60 m) kendiliğinden başlar, kısa bildirim
   çıkar; anlatımlar üst üste binmez; "Dinle" ile elle de başlar.
7. **Kaynak göster:** her anlatımın altında kaynak ve "Yanlış bilgi
   bildir".

## Tasarım dili

| Öğe | Değer |
|---|---|
| Vurgu (Kiremit) | `#C94A2B`, yalnızca rota çizgisi ve ana düğme |
| Yazı | Figtree (Google Fonts, ücretsiz); başlık 30 px kalın |
| Metin / gri | `#222222` / `#6A6A6A` |
| Çizgiler / zemin | `#DDDDDD`, `#EBEBEB` / beyaz, `#F7F7F7` |
| Köşeler | Kart 14, düğme 8, hap tam yuvarlak; alt pencere 24 |
| Gölge | Tek kat, hafif |
| Harita | Kara `#F2F0EB`, sokak beyaz, su `#C9DDE6`, park `#DCE8D2`; uydu ve karma seçilebilir |
| Pinler | Beyaz hap: küçük fotoğraf + ad; aktif yer siyah; planda gün numarası siyah daire |
| Küre | Açık renkli küre, şehirler fotoğraflı pin |
| Alt çubuk | Solda bilgi, sağda Kiremit ana düğme |
| Yüzen kontroller | Beyaz hap sekme çubuğu, siyah "+" daire, "Planla / Yürü" |

## Kapsam

| Özellik | Aşama |
|---|---|
| Paylaşma menüsünden ekleme, sormadan tahmin + "Değiştir" / "Geri al" | MVP |
| Instagram, TikTok veri dosyası ve Google Maps (Takeout) aktarımı | MVP |
| Küre ana sayfa, Gezilerim / Kayıtlarım, Kayıtlarım süzme | MVP |
| Gün ve tempo, otomatik rota, gerçek sokaklardan çizim | MVP |
| Şehir planı, "+" menüsü, kendi yerin, şehir ekleme | MVP |
| Popüler yerler (Wikipedia) ve yer sayfası | MVP |
| Tripadvisor puanı | MVP, Oguz hesabı açınca |
| Dinle, yürürken otomatik anlatım, yön tarifi | MVP |
| İnternetsiz indirme | MVP |
| Türkçe ve İngilizce arayüz ve ses | MVP |
| Fotoğrafla yer ekleme | MVP |
| Kaydırmalı öneri kartları | Aşama 2 |
| Apple Watch, yeni şehirler, kendi rota motoru | Aşama 3 |
| Rezervasyon, uçuş, konaklama, ödeme, sosyal, gezi videosu, basılı kitap, masraf takibi | Kapsam dışı |

## Açık sorular

- Anlatımı yazacak ücretsiz yapay zekâ servisi ve daha doğal ücretsiz ses.
- Tripadvisor hesabı (Oguz, yazılım aşamasında adım adım).
- Tripadvisor puanı ile Wikivoyage ipuçları aynı sayfada olabilir mi?
- Instagram/TikTok veri dosyası içeriği ilk gerçek denemede doğrulanacak.
- Apple Haritalar yer kartında fotoğraf ve saat görünüyor mu?
- Anlatımın başlama mesafesi Tokyo testinde ayarlanacak.

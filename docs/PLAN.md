# TravelApp — Plan

Kaynak: `TravelApp.docx` ("Seyahat Uygulaması: Araştırma ve Ürün
İskeleti", 23 Eki 2026) ve Oguz'un 23 Eki 2026'da paylaştığı proje
scope'u. Kesinleşen kararlar `CLAUDE.md` → Kararlar bölümündedir.
Henüz yazılım aşamasına geçilmedi.

## 1. Amaç

Kullanıcının Instagram, TikTok ve Google Maps'te kaydettiği yerlerden
otomatik gezi rotası çıkaran, yürürken telefon cepteyken tek kulaklıkla
yönlendiren ve yerlerin tarihini ve hikâyesini anlatan iOS seyahat
rehberi.

**Benzersiz değer (taslak):** "Instagram, Google Maps ve TikTok'ta
kaydettiğin yerleri tek dokunuşla topla; telefon cebinde, tek kulaklıkla,
kendi rotanda yürüyen bir tur rehberi seni yönlendirsin ve hikâyeleri
anlatsın."

Neden bu fark önemli? Ücretsiz bir yapay zekâya "bana anlat" demek zaten
mümkün. Bu ürünün yapması gereken, yapay zekânın tek başına yapamadığı üç
şey:

1. Dağınık kayıtları (Instagram, TikTok, Google Maps) tek yerde toplayıp
   geziye çevirmek.
2. Ekrana bakmadan, konuma göre sıralı ve kesintisiz sesli yönlendirme ve
   anlatım.
3. Hızdan çok "güzel sokak" mantığıyla çizilmiş yürüyüş rotası.

## 2. Kullanıcılar

- Yurt dışından gelen turistler ve yurt içi yerli gezginler.
- Dil: Türkçe ve İngilizce. Fiyat: ücretsiz.
- Şehirler kullanıcının kayıtlarına göre; Tokyo öncelikli.
- İlk tester: Oguz (kendi Instagram kayıtlarıyla).

## 3. Kullanıcı akışı

1. Başka bir uygulamada yeri paylaş (iOS paylaşma menüsü).
2. Uygulama yeri bulur ve şehrinin listesine ekler.
3. Gün sayısı ve tempo seç (rahat, normal, tempolu).
4. Rota hazır, gerekirse düzenle.
5. Kulaklığı tak, yürü ve dinle.

## 4. Ana özellikler (ilk sürüm / MVP)

| Özellik | Kapsam | Kabul ölçütü |
|---|---|---|
| Kayıt aktarımı | iOS paylaşma menüsü; Instagram/TikTok linki, ekran görüntüsü, Google Maps linki. Yer bulma sırası: konum etiketi → açıklama, hashtag ve etiketler (yapay zekâ + harita aramasıyla doğrulama) → fotoğraf/video karesi (görsel okuyan yapay zekâ). Onay kartı yok: güven yüksekse otomatik ekle + "Geri al"; düşükse 2-3 aday, tek dokunuş; bulunamazsa "Yeri belirle" etiketiyle bekler. | Paylaşmadan eklemeye 3 saniyenin altı; 20-30 gerçek post ile doğruluk oranı ölçülür |
| Google Maps liste aktarımı | Google Takeout dosyası yüklenir: Yıldızlı yerler (GeoJSON, koordinatlı) doğrudan eklenir; Favoriler, "Gitmek istiyorum" ve özel listeler (CSV, koordinatsız) başlık ve linkten haritada eşleştirilir. Önce dosya yükleme, sonra liste linki paylaşma denenir | Listedeki yerler doğru konumda ve doğru şehre eklenir |
| Gezim | Şehre göre liste ve harita (Apple Haritalar), her yer için küçük ikon ve fotoğraf | Yerler haritada doğru konumda |
| Otomatik rota | Gün sayısı ve tempo seçimi; bölgeye göre gruplama, her gün tek bölgede kalmaya çalışma, sıralama; "güzel sokak puanı" ile yürüyüş rotası; bölgeler arası toplu taşıma veya taksi önerisi | Rota 5 saniyeden kısa sürede; tempoya göre durak sayısı değişir |
| Düzenleme | Sürükle sırala, kaydırarak sil, "Günü hafiflet" düğmesi, her işlemde geri al | Metin yazma gerektirmez |
| Yürüyüş modu | Telefon cepteyken tek kulaklıkla (mono) yön tarifi; konuma göre otomatik anlatım; anlatımlar üst üste binmez; çevrimdışı ses ve harita; sade ekran (sıradaki durak, mesafe, duraklat/devam) | 30 dk yürüyüşte kesintisiz ses, makul pil tüketimi |
| Anlatım | Yapay zekâ üretir, kaynak gösterir, birden fazla açık kaynakla çapraz kontrol; aynı yer için bir kez üretilip saklanır; "Yanlış bilgi bildir" düğmesi | Her anlatımda en az bir kaynak |
| Dil | Arayüz ve ses Türkçe ve İngilizce; kullanıcı anlatım dilini seçer; Tokyo gibi şehirlerde yer adı okunuşları kontrol edilir | İki dilde de tam akış |

**Tempo başlangıç varsayımları** (kullanıcı testiyle ayarlanacak):

| Tempo | Günde durak | Durak başı süre | Mola | Yürüyüş |
|---|---|---|---|---|
| Rahat | 3-4 | uzun, içeri girmeye zaman | 2 | az |
| Normal | 5-6 | orta | 1-2 | orta |
| Tempolu | 7+ | kısa, dışarıdan görüp geçme | 1 | uzun |

**MVP ekranları:** Kaydet, Gezim (liste + harita), Rota, Yürüyüş modu,
İndirme (çevrimdışı). Öneriler ekranı Aşama 2.

## 5. Kapsam dışı

Rezervasyon, ödeme, sosyal özellikler, kendi keşif platformu, masraf
takibi. Kaydırmalı öneri kartları Aşama 2'de, Apple Watch Aşama 3'te.

## 6. Aşamalar

- **Aşama 0 — deneme:** 20-30 gerçek post ile kayıt aktarımı denemesi
  (Oguz'un Instagram kayıtları); Tokyo'da sesli yürüyüş prototip testi;
  10-15 hedef kullanıcıyla kısa görüşme; değer cümlesinin
  anlaşılırlığını ölçmek.
- **Aşama 1 — MVP:** paylaşma menüsünden yer ekleme, Google Maps liste
  aktarımı, gün sayısı ve tempo seçimi, otomatik rota, yürüyüş modu ve ses, çevrimdışı indirme.
- **Aşama 2:** kaydırmalı öneri kartları (rotaya yakın yerler, oturumda
  en fazla 8-10 kart).
- **Aşama 3:** Apple Watch (sıradaki durak, duraklat/devam), yeni
  şehirler, kendi yürüyüş rota motoru.

İlk haftaların sırası: 1) kayıt aktarımı deneyi, 2) rota ve harita,
3) yürüyüş modu ve ses, 4) çevrimdışı ve maliyet kontrolü.

## 7. Teknik yön (öneri, uygulamada doğrulanacak)

Swift ve SwiftUI; Apple MapKit (harita ve yürüyüş yönlendirmesi);
Share Extension (paylaşma menüsü); arka planda konum; ses için Apple'ın
cihazdaki ses sentezleyicisi veya bulut ses servisi; ince bir sunucu
katmanı (yer çıkarma, anlatım üretimi, önbellek). Bu proje için ayrı
kurulum yapılır.

## 8. Riskler

| Risk | Önlem |
|---|---|
| Rakip (ör. Feedtrip) ses özelliği ekler | Ses ve çevrimdışı yürüyüş kalitesine öncelik |
| Anlatımda yanlış bilgi | Çapraz kaynak kontrolü, kaynak gösterme, bildirim düğmesi |
| Instagram/TikTok verisine erişim sınırlı | Link ve ekran görüntüsü yolu birlikte; kazıma (scraping) yok |
| Arka planda konum: pil ve iOS izinleri | Erken, gerçek cihazda test |
| Ücretsiz kalma zorunluluğu | Yalnızca ücretsiz servisler, anlatımları bir kez üretip saklama |
| Telif ve gizlilik | Sosyal medyadan yer çıkarma ve konum verisi için KVKK/GDPR kontrolü |

## 9. Açık sorular

1. **Sıfır bütçeyle yapay zekâ ve ses:** Hangi ücretsiz servislerin
   kullanılacağına ve limit dolunca ne olacağına yazılım aşamasında
   Oguz ile birlikte karar verilecek.
2. **Apple Developer hesabı (çözüldü, 23 Eki):** Aşama 0-1 için ücretsiz
   hesap yeterli. App Store'a çıkmadan önce yeniden konuşulacak.
3. **Sunucu:** "İnce sunucu katmanı" hangi ücretsiz hizmette çalışacak?
4. **Türkçe ve Japonca yer adları:** Tokyo'da yer adı okunuşları ve
   Türkçe/İngilizce ses kalitesi nasıl sağlanacak?
5. **Telif ve gizlilik (KVKK, GDPR):** sosyal medya içeriğinden yer
   çıkarma ve konum verisi için hangi kurallar uygulanacak?
6. **Kullanıcı karar verme davranışı:** güncel veri yok; 10-15 kullanıcı
   görüşmesiyle kapatılacak.

## 10. Öneriler / notlar

Onay bekleyen öneriler buraya yazılır.

- **2026-10-23 · Fotoğraf çekerek yer ekleme** (Oguz'un notu): kamera ile tabela/bina çekilir, görsel okuyan yapay zekâ + telefon konumu ile yer bulunur. Taslak: `design/ekranlar/AltCamera.dc.html`. MVP'ye alınıp alınmayacağı Oguz'a soruldu.
- **2026-10-23 · Instagram/TikTok kayıtlarını toplu getirme** (Oguz'un notu: "giriş yapıp kayıtlara erişim"): Instagram ve TikTok, kaydedilenlere başka uygulamaların resmî yoldan erişmesine izin vermiyor; kazıma (scraping) risk tablosunda dışarıda. Önerilen yol: kullanıcının kendi "verilerini indir" dosyasını (Instagram: Hesap Merkezi → Bilgilerini indir → Kaydedilenler; TikTok: Verilerini indir → Favoriler) yüklemesi, Google Takeout gibi. Dosyanın içeriği ilk denemede doğrulanacak. Ek olarak: uygulama açılınca kopyalanmış linki algılayıp "Eklensin mi?" sormak. Taslak: `design/ekranlar/AltAddPlace.dc.html`.
- **2026-10-23 · Emin olunamayan yerde sormadan tahmin** (Oguz'un notu: aday seçme ekranı efor istiyor): en olası yer "Tahmini konum" etiketiyle otomatik eklenir, kullanıcı isterse "Değiştir"e basar. Bu, Kararlar'daki "düşükse 2-3 aday arasından seçilir" kararını değiştirir; Oguz'un onayı bekleniyor. Taslak: `design/ekranlar/AltShareAuto.dc.html`.
- **2026-10-23 · Harita ağırlıklı rota ve yürüyüş** (Oguz'un notları): rota ekranı haritada fotoğraflı işaretlerle, yürüyüş modu harita + büyütülebilen alt pencere. Taslaklar: `AltRouteMap.dc.html`, `AltWalkMap.dc.html`.
- **2026-10-24 · Polarsteps'ten ilham, harita odaklı akış** (Oguz'un Polarsteps ekranları): küre ana sayfa, şehir planında harita üstte + günler altta, "+" menüsü (yer, kayıtlarından, kendi yerin, şehir, rotayı yeniden düzenle), "Planla / Yürü" geçişi, "Kayıtlarım" koleksiyonu, kendi yerini oluşturma. Taslaklar: `design/ekranlar/P-*.dc.html`. Oguz'un onayı bekleniyor.
- **2026-10-24 · Popüler yerler için Tripadvisor yerine ücretsiz kaynaklar**: Tripadvisor Content API'de ayda 5.000 çağrı bedava ama kayıtta kredi kartı isteniyor; bilgiyi saklamak (internetsiz kullanım), değiştirmek (anlatım için özetlemek) ve başka kullanıcı içeriğiyle yan yana göstermek yasak; sesli okumaya izin veren madde yok. Öneri: yer bulma ve saatler Apple Haritalar (iPhone uygulamasında ücretsiz), popüler yerler ve açıklamalar Wikipedia + Wikivoyage (CC BY-SA, kaynak gösterilerek özetlenip sesli okunabilir), ses iPhone'un kendi sesi. **Karar (2026-10-24):** Oguz Tripadvisor'ı da denemeyi seçti; yalnızca puan için kullanılacak (bkz. CLAUDE.md Kararlar). Hesap açılınca Tripadvisor'ın gösterim kuralları (logo, puan görseli, başka içerikle yan yana gösterme) yeniden okunacak.
- **2026-10-24 · Her yer sayfasında "Dinle" ve yürürken küçük sesli çalar**: anlatım yere yaklaşınca kendiliğinden başlar, harita kapanmaz. Polarsteps'te bu yok; ürünün asıl farkı. Taslaklar: `P-Yer.dc.html`, `P-Yuruyus.dc.html`.

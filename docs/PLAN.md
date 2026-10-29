# TravelApp — Plan

Kaynak: `TravelApp.docx` ("Seyahat Uygulaması: Araştırma ve Ürün
İskeleti", 23 Eki 2026) ve Oguz'un 23 Eki 2026'da paylaştığı proje
scope'u. Kesinleşen kararlar `CLAUDE.md` → Kararlar bölümündedir.
Yazılım aşaması 24 Eki 2026'da başladı; derleme ve kurulum için bkz.
`docs/GELISTIRME.md`.

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
3. Gün sayısını seç (tempo seçimi şimdilik yok, 2026-10-29).
4. Rota hazır, gerekirse düzenle.
5. Kulaklığı tak, yürü ve dinle.

## 4. Ana özellikler (ilk sürüm / MVP)

| Özellik | Kapsam | Kabul ölçütü |
|---|---|---|
| Kayıt aktarımı | iOS paylaşma menüsü; Instagram/TikTok linki, ekran görüntüsü, Google Maps linki. Yer bulma sırası: konum etiketi → açıklama, hashtag ve etiketler (yapay zekâ + harita aramasıyla doğrulama) → fotoğraf/video karesi (görsel okuyan yapay zekâ). Onay kartı yok: güven yüksekse otomatik ekle + "Geri al"; düşükse 2-3 aday, tek dokunuş; bulunamazsa "Yeri belirle" etiketiyle bekler. | Paylaşmadan eklemeye 3 saniyenin altı; 20-30 gerçek post ile doğruluk oranı ölçülür |
| Google Maps liste aktarımı | Google Takeout dosyası yüklenir: Yıldızlı yerler (GeoJSON, koordinatlı) doğrudan eklenir; Favoriler, "Gitmek istiyorum" ve özel listeler (CSV, koordinatsız) başlık ve linkten haritada eşleştirilir. Önce dosya yükleme, sonra liste linki paylaşma denenir | Listedeki yerler doğru konumda ve doğru şehre eklenir |
| Gezim | Şehre göre liste ve Google Maps gibi çalışan harita (Apple Haritalar: konumum, uydu görünümü, haritadaki bir yere dokunup kaydetme). Yol tarifi uygulamanın içinde, araba GPS'i gibi sesli yürüyüş rehberi (Haritalar uygulamasına geçmez). Her yer türünün renk ve simgesiyle görünür (müze, kafe, tapınak...). Polarsteps'teki "Add a spot" gibi sade "Yer ekle" listesi (ana sayfada sağ alttaki büyüteçten): arama, kayıtlı yerler, popüler yerler, tek dokunuşla "+". Yer penceresi yarım ekran açılır, yukarı kaydırınca %70'e çıkar; fotoğrafa dokununca tam ekran açılır | Yerler haritada doğru konumda; türü pinden anlaşılıyor |
| Otomatik rota | Gün sayısı seçimi (tempo şimdilik yok); her yerin gününü kullanıcı seçer (otomatik bölme yok, 2026-10-29); gün içinde yürüme sırası otomatik; bölgeye göre gruplama, her gün tek bölgede kalmaya çalışma, sıralama; "güzel sokak puanı" ile yürüyüş rotası; bölgeler arası toplu taşıma veya taksi önerisi | Rota 5 saniyeden kısa sürede; hiçbir yer dışarıda kalmaz |
| Düzenleme | Şehir planında tek gün ya da "Tüm yerler" görünür, gün tek düğmeden değişir; yeri başka güne taşıma (yer penceresinde "n. gün ⌄" düğmesi, listede basılı tutup menü), rotadan çıkarma, her işlemde geri al. Yere bakarken harita görünür kalır ve o yere yakınlaşır | Metin yazma gerektirmez |
| Yürüyüş modu | Telefon cepteyken tek kulaklıkla (mono) yön tarifi; konuma göre otomatik anlatım; anlatımlar üst üste binmez; çevrimdışı ses ve harita; sade ekran (sıradaki durak, mesafe, duraklat/devam) | 30 dk yürüyüşte kesintisiz ses, makul pil tüketimi |
| Anlatım | Yapay zekâ üretir, kaynak gösterir, birden fazla açık kaynakla çapraz kontrol; aynı yer için bir kez üretilip saklanır; "Yanlış bilgi bildir" düğmesi | Her anlatımda en az bir kaynak |
| Dil | Arayüz Türkçe ve İngilizce; anlatım şimdilik hep Türkçe (2026-10-29): Türkçe Wikipedia yoksa İngilizcesi Türkçeye çevrilir (önce iPhone çevirisi, olmazsa Gemini/Groq ücretsiz katmanı); anlatım çalarken altta her sayfada duraklat / 10 sn geri / 10 sn ileri çubuğu; Tokyo gibi şehirlerde yer adı okunuşları kontrol edilir | İki dilde de tam akış |

**Tempo başlangıç varsayımları** (tempo seçimi 2026-10-29'da şimdilik kaldırıldı; geri gelirse kullanılır):

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
  aktarımı, gün sayısı seçimi, otomatik rota, yürüyüş modu ve ses, çevrimdışı indirme.
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
   24 Eki: Oguz'un mevcut ücretli Developer hesabı var; TestFlight'a
   bağlantı yazılım iskeleti kurulduktan sonra yapılacak.
3. **Sunucu:** "İnce sunucu katmanı" hangi ücretsiz hizmette çalışacak?
4. **Türkçe ve Japonca yer adları:** Tokyo'da yer adı okunuşları ve
   Türkçe/İngilizce ses kalitesi nasıl sağlanacak?
5. **Telif ve gizlilik (KVKK, GDPR):** sosyal medya içeriğinden yer
   çıkarma ve konum verisi için hangi kurallar uygulanacak?
6. **Kullanıcı karar verme davranışı:** güncel veri yok; 10-15 kullanıcı
   görüşmesiyle kapatılacak.

## 10. Öneriler / notlar

Onay bekleyen öneriler buraya yazılır.

- 2026-10-24: Gemini ve Groq anahtarları şimdilik derleme sırasında uygulamanın içine
  konuyor (test aşamasında yalnızca Oguz kullanıyor). App Store'a çıkmadan
  önce anahtarı ücretsiz bir sunucu katmanına (ör. Cloudflare Workers
  ücretsiz katmanı) taşımak gerekir; aksi halde anahtar uygulamadan
  okunabilir. Oguz'a sorulacak.
- 2026-10-29 (Oguz'un fikri, sonra): **Gün önerisi.** Bir yer, yakınındaki
  yerlerin çoğunun olduğu günden farklı bir güne eklenmişse uygulama bunu
  söyleyip "Bu yer 2. gündeki yerlere yakın, oraya taşıyalım mı?" diye
  önerebilir. Şimdilik yapılmadı; Oguz'a sorulacak.

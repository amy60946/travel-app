# Arayüz taslağı (iOS, MVP)

Tıklanabilir önizleme: https://claude.ai/artifact/AM6jvTbmPCRyLwz1okjmVh
(Yalnızca Oguz açabilir; paylaşmak için sayfadaki *Share* menüsü.)

`ekranlar/` klasörü önizlemenin kaynak dosyalarıdır (her ekran bir dosya).
Yazılım aşamasında SwiftUI ekranları bu taslağa göre yapılacak.

| # | Ekran | Dosya | PLAN.md karşılığı |
|---|---|---|---|
| 1 | Gezim (ana ekran, şehirler) | Main.dc.html | Gezim |
| 2 | Paylaş → otomatik eklendi + Geri al | ShareAdded.dc.html | Kayıt aktarımı (güven yüksek) |
| 3 | Paylaş → 2-3 aday / "Yeri belirle" | ShareChoose.dc.html | Kayıt aktarımı (güven düşük / bulunamadı) |
| 4 | Yer ekle + Google Maps liste aktarımı | Import.dc.html | Google Maps liste aktarımı |
| 5 | Şehir: liste / harita | City.dc.html | Gezim (liste + harita) |
| 6 | Gün sayısı, tempo, anlatım dili | Plan.dc.html | Otomatik rota, Dil |
| 7 | Rota: günler, sil, sırala, "Günü hafiflet", geri al | Route.dc.html | Otomatik rota, Düzenleme |
| 8 | Yürüyüş modu (sade, karanlık ekran) | Walk.dc.html | Yürüyüş modu, Anlatım |
| 9 | Çevrimdışı indirme | Download.dc.html | İndirme |


### Alternatifler (Oguz'un 23 Eki notlarına göre)

| # | Ekran | Dosya | Hangi nota cevap |
|---|---|---|---|
| B7 | Rota: harita ağırlıklı, fotoğraflı işaretler, alttan kaydırmalı kartlar | AltRouteMap.dc.html | "Harita görünümü ağırlıklı olmalı, minimum okuma" |
| B8 | Yürüyüş: harita kalır, altta büyütülebilen pencere | AltWalkMap.dc.html | "Tam ekran anlamsız, harita kalsın" |
| B3 | Paylaş: emin olunamazsa sormadan en olası yeri ekler, "Değiştir" ile düzeltilir | AltShareAuto.dc.html | "Bu ekran kullanıcıya top atıyor" |
| B4 | Yer ekle: kopyalanan link algılama, fotoğraf çek, Instagram/TikTok/Google veri dosyası | AltAddPlace.dc.html | "Instagram/TikTok ile giriş", "Fotoğraf çekme" |
| B4b | Fotoğraf çekerek yer ekleme | AltCamera.dc.html | "Fotoğraf çekme de eklenebilir" |

Notlar: yerler ve sayılar örnektir (Tokyo); harita ve fotoğraflar yer
tutucudur. Arayüz Türkçe çizildi, İngilizce çevirisi aynı ekranlar olacak.

### Stil alternatifleri (24 Eki, sayfa: "Stil alternatifleri")

Apple'ın tasarım dilinde, sakin ve az renkli üç stil; her biri Rota,
Yürüyüş ve Yer ekle ekranlarıyla gösterildi. Biri seçilecek, sonra bütün
ekranlar o stile geçirilecek.

| Stil | Dosyalar | Renk |
|---|---|---|
| A | A-Rota, A-Yuruyus, A-YerEkle | Açık zemin, tek mavi vurgu |
| B | B-Rota, B-Yuruyus, B-YerEkle | Açık zemin, tamamen siyah-beyaz |
| C | C-Rota, C-Yuruyus, C-YerEkle | Koyu zemin, tek yeşil vurgu |

### Marka dili (24 Eki, sayfa: "Marka dili (yeni)")

Büyük seyahat uygulamalarının (Airbnb, Tripadvisor, Komoot, Polarsteps,
Citymapper, GetYourGuide, Booking.com) tasarım dilleri incelendi
(`Referanslar.dc.html`). Üç marka yönü çıkarıldı; her biri marka kartı +
Rota + Yürüyüş ekranıyla gösterildi. Yazı karakterleri Google Fonts'tan,
ücretsiz ve açık lisanslı.

| Yön | Dosyalar | Yazı | Renk | İmza öğe |
|---|---|---|---|---|
| 1 · Defter | M1-* | Fraunces + Source Sans 3 | Kâğıt, mürekkep lacivert, damga kırmızısı | Kesik çizgili rota, pul gibi yer işaretleri |
| 2 · İz | M2-* | Outfit | Beyaz, çam yeşili, iz yeşili | Kalın düz yeşil rota |
| 3 · Ses | M3-* | Space Grotesk + Inter + DM Mono | Koyu gece, kehribar | Anlatılan yerde ses halkaları |

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

Notlar: yerler ve sayılar örnektir (Tokyo); harita ve fotoğraflar yer
tutucudur. Arayüz Türkçe çizildi, İngilizce çevirisi aynı ekranlar olacak.

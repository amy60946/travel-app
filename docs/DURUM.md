# DURUM — karar ve iş günlüğü

Her oturum sonunda tek satır eklenir: `tarih · ne değişti · kim ne yapmalı`.
Kararların tam listesi `CLAUDE.md` → Kararlar bölümündedir.

- 2026-10-23 · TravelApp.docx ve yeni scope okundu; CLAUDE.md, docs/PLAN.md ve docs/DURUM.md oluşturuldu; 4 karar alındı (tempo MVP'de, onay kartı yok, test Tokyo'da, bütçe sıfır) · Oguz: PR'ı inceleyip onaylasın, PLAN.md'deki açık soruları (özellikle 1 ve 2) yanıtlasın
- 2026-10-23 · Google Maps liste aktarımı ilk sürüme alındı; ücretsiz Apple hesabı Aşama 0-1 için yeterli; yapay zekâ servisleri yazılım aşamasında birlikte seçilecek · Oguz: PR #1'i birleştirsin
- 2026-10-24 · iOS iskelet uygulaması (ios/, SwiftUI, 4 sekme + gün/tempo seçimi), GitHub Actions ile otomatik derleme/test ve imzasız .ipa, kurulum rehberi docs/GELISTIRME.md eklendi · Oguz (Mac kullanıyor): PR'ı birleştirsin; sonra mevcut Developer hesabı TestFlight'a bağlanacak
- 2026-10-24 · Ürün belgesi (docs/URUN.md) Oguz tarafından onaylandı; TestFlight yükleme işi, uygulama simgesi ve kurulum adımları eklendi · Oguz: docs/GELISTIRME.md → TestFlight kurulumu adımlarını yapsın, sonra Actions → TestFlight → Run workflow
- 2026-10-24 · İlk ekranlar kodlandı (küre, Kayıtlarım, şehir planı, yer sayfası, yer ekle, kendi yerin, yürüyüş; rota planlayıcı; Wikipedia + Apple Haritalar; 11 test geçti) · Oguz: PR #4'ü birleştirsin ve TestFlight adımlarını yapsın; sonraki adım: paylaşma menüsü ve veri dosyası aktarımı
- 2026-10-24 · Google Maps liste aktarımı ve İndirilenler (internetsiz anlatım + yürüyüş yolu) eklendi; tüm testler yeşil · Oguz: TestFlight adımları + PR #4'ü birleştir; fotoğrafla ekleme için yöntem kararı
- 2026-10-24 · PR #4 birleşti; ilk TestFlight denemesinde Apple, uygulamanın iOS 26 SDK (Xcode 26) ile derlenmesini istedi; derleme işleri en yeni Xcode'u seçecek şekilde güncellendi · Claude: yeniden yükle; Oguz: TestFlight'tan dene
- 2026-10-24 · Fotoğraftan ve kopyalanan yazıdan yer bulmada Gemini + Groq ücretsiz yapay zekâları birlikte kullanılıyor (her fotoğrafta resim + okunan yazı gönderilir) · Oguz: GitHub Secrets'a GEMINI_API_KEY ve GROQ_API_KEY ekle; Claude: PR'ı yeşilse birleştir, TestFlight'a yükle
- 2026-10-24 · Instagram/TikTok veri dosyası aktarımı (kazımasız: TikTok resmi açıklama + yapay zekâ tahmini, bulunamayanlar "Yeri belirle" listesine) ve onaylı tasarıma göre arayüz düzeltmeleri (ana sayfa listesi, taşan fotoğraflar, yer ekle araması, sade renkler); ekran görüntüleri her [ekran] commit'inde otomatik çekiliyor · Claude: PR #7'yi yeşilse birleştir, TestFlight'a yükle; Oguz: Instagram ve TikTok verisini indirip uygulamada dene
- 2026-10-24 · Uygulamadaki Instagram indirme adımları Instagram'ın yeni menü adlarına (Export your information) göre güncellendi · Claude: PR yeşilse birleştir, TestFlight'a yükle; Oguz: Instagram verisini dışa aktar

# CLAUDE.md — TravelApp çalışma kuralları

Bu dosya, bu depoda çalışan her Claude oturumunun ilk okuyacağı yerdir.
Bu proje başka hiçbir projeyle bağlantılı değildir; başka projelerin
kodunu, sunucusunu (ör. Supabase) veya anahtarlarını kullanma.

## Proje sahibi ve iletişim

- Proje sahibi: Oguz (GitHub: `amy60946`). Yazılımcı değil.
- Her zaman **Türkçe ve sade dille** konuş. Teknik terim gerekiyorsa
  kısaca ne olduğunu açıkla.
- Bir şey yapması gerekiyorsa **adım adım** anlat ve **nereye
  tıklayacağını** söyle (ör. "GitHub'da depoya gir → üstte *Settings* →
  soldan *Secrets and variables* → *Actions* → *New repository secret*").

## Güvenlik

- Şifre, API anahtarı, token veya lisans kodunu **sohbete yapıştırmasını
  asla isteme**. Bunlar GitHub Secrets'a ya da ilgili servisin paneline
  girilir; sen sadece hangi isimle nereye gireceğini söylersin.
- Gizli bilgiyi koda, dokümana veya commit'e yazma.

## Kapsam ve kararlar

- **Kapsam dışına çıkma.** Kapsam `docs/PLAN.md`'de yazılıdır.
- Aklına gelen öneriler **not olarak** yazılır (`docs/PLAN.md` →
  "Öneriler / notlar") ve Oguz'a sorulur; onay gelmeden uygulanmaz.
- **Belirsiz kararda tahmin etme**, kısa bir soru sor.
- Oguz'un verdiği her kararı, tarihiyle aşağıdaki **Kararlar** bölümüne
  ekle. Bir sonraki oturum bunları buradan öğrenir.
- **Bütçe sıfırdır** (bkz. Kararlar). Ücretli bir servis, plan veya
  hesap gerektiren her adımdan önce dur ve sor.

## Doğrulama

- Değişiklikten önce ve sonra doğrula: test çalıştır, derle (kod varsa).
- "Bitti" demeden önce **kanıt göster**: test/derleme çıktısı, ekran
  görüntüsü veya değişen dosyaların listesi.
- Doğrulanamayan bir şey varsa bunu açıkça söyle.

## Oturum sonu

- Her oturumun sonunda `docs/DURUM.md` dosyasına **tek satır** ekle:
  `tarih · ne değişti · kim ne yapmalı`

## Kararlar

Kaynak: `TravelApp.docx` (23 Eki 2026) ve Oguz'un proje sohbetindeki
cevapları.

| Tarih | Karar |
|---|---|
| 2026-10-23 | Hedef kitle: yurt dışından gelen turistler ve yurt içi yerli gezginler. |
| 2026-10-23 | Dil: arayüz ve ses Türkçe ve İngilizce; kullanıcı anlatım dilini seçer. |
| 2026-10-23 | Fiyat: şimdilik ücretsiz. |
| 2026-10-23 | Platform: önce iOS, sonra Apple Watch (Aşama 3). |
| 2026-10-23 | Şehirler kullanıcının kayıtlarına göre belirlenir; Tokyo öncelikli, İstanbul ile sınırlı değil. |
| 2026-10-23 | İçerik: manuel küratörlük yok; kayıt aktarımı, rota ve anlatım otomatik üretilir, anlatımlar kaynaklı olur. |
| 2026-10-23 | Kapsam dışı: rezervasyon, ödeme, sosyal özellikler, kendi keşif platformu. |
| 2026-10-23 | Kişiselleştirme (gün sayısı ve tempo seçimi: rahat / normal / tempolu) **ilk sürümde (MVP)** olacak. Kaydırmalı öneri kartları Aşama 2'de kalır. |
| 2026-10-23 | Kayıtta **onay kartı yok**: güven yüksekse otomatik eklenir ve "Geri al" gösterilir; düşükse 2-3 aday arasından tek dokunuşla seçilir; bulunamazsa "Yeri belirle" etiketiyle bekler. |
| 2026-10-23 | Aşama 0 sesli yürüyüş testi **Tokyo**'da yapılacak. İlk tester Oguz; kendi Instagram kayıtlarını aktararak deneyecek. |
| 2026-10-23 | **Bütçe yok; her şey ücretsiz olmalı.** Yalnızca ücretsiz servisler ve ücretsiz kullanım katmanları kullanılır; ücret çıkabilecek her şey önce Oguz'a sorulur. |
| 2026-10-23 | Bu proje için ayrı kurulum yapılır; başka projelerin Supabase'i veya anahtarları kullanılmaz. |
| 2026-10-23 | **Google Maps liste aktarımı** (Google Takeout ile Yıldızlı yerler, Favoriler, "Gitmek istiyorum" ve özel listeler) **ilk sürüme (MVP)** alındı. |
| 2026-10-23 | Yer bulma, anlatım ve ses için hangi ücretsiz yapay zekâ servislerinin kullanılacağına yazılım aşamasında Oguz ile birlikte karar verilecek. |
| 2026-10-23 | Aşama 0-1 için ücretsiz Apple hesabı yeterli (uygulama Oguz'un telefonuna kısa süreli kurulur); ücretli Apple Developer hesabı şimdilik alınmayacak. |
| 2026-10-24 | Oguz'un **mevcut ücretli Apple Developer hesabı** var (yeni ücret çıkmaz). Önce yazılım kurulup yapılandırılacak; hesap ve TestFlight bağlantısı sonra yapılacak. |
| 2026-10-24 | Ürün belgesi (`docs/URUN.md`) onaylandı; yazılım bu belgeye göre yapılır. TestFlight kurulumu başlatıldı. |

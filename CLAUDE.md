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
| 2026-10-24 | Bundle ID (uygulama kimliği): `io.travelapp.ios`. |
| 2026-10-24 | Fotoğrafla ekleme: **ikisi birden**. Önce iPhone yazı tanıma + konum (ücretsiz, internetsiz); yazı okunamaz ya da eşleşmezse Google Gemini ücretsiz katmanı (anahtar `GEMINI_API_KEY`, GitHub Secrets). |
| 2026-10-24 | Testler yeşil olunca PR'ları **Claude birleştirir** ve TestFlight yüklemesini başlatır; Oguz telefonda dener. |
| 2026-10-24 | Yapay zekâ yalnızca yedek değil: fotoğrafla eklemede resim + okunan yazı her seferinde **Gemini ve Groq ücretsiz katmanlarına** birlikte sorulur; kopyalanan yazıdan (ör. Instagram açıklaması) yer bulma da bu iki servisi kullanır. Anahtarlar `GEMINI_API_KEY`, `GROQ_API_KEY` (GitHub Secrets). DeepSeek ücretli olduğu için kullanılmaz. |
| 2026-10-24 | Instagram/TikTok veri dosyası aktarımı açıldı. **Kazıma yok**: TikTok açıklaması TikTok'un resmi oEmbed servisinden, Instagram'da yalnızca hesap ve koleksiyon adından yapay zekâ tahmini; bulunamayan gönderiler tek dokunuşla açılan "Yeri belirle" listesine girer. Resmi Meta yolu şimdilik yok. |
| 2026-10-24 | Arayüz iyileştirmesi: önce her ekranın simülatör görüntüsü alınıp onaylı tasarımla (Polarsteps ilhamı panosu) karşılaştırılır, farklar düzeltilir. |
| 2026-10-24 | Instagram aktarımı kısaltıldı ("Kısa yol + otomatik bulma"): uygulamadaki **Instagram'dan al** düğmesi Meta'nın resmi dışa aktarma sayfasını açar; uygulama .zip'i kendisi açar; kullanıcı bir kez İndirilenler klasörüne izin verirse yeni inen Instagram/TikTok/Google dosyası kendiliğinden bulunup aktarılır; dosya "Paylaş → TravelApp" ile de açılır. Instagram'a girip otomatik tıklama yok; Meta resmi aktarım hedefi olmak (şirket doğrulaması + sunucu) şimdilik yok. |
| 2026-10-24 | Blogger/gezgin gönderileri için **ekran görüntüsüyle ekleme**: "Yeri belirle"de gönderi açılır, ekran görüntüsü alınır; uygulama açıklamayı ve konum etiketini okuyup yeri ekler (Fotoğraflar tam erişimi verilirse dönünce kendiliğinden). Oguz "İkisi birden" (Google araması + ekran görüntüsü) seçti; Google araması Gemini ücretsiz katmanında kota sıfır olduğu için yapılmadı; Gemini'nin linki okuma aracı (ücretsiz) Instagram gönderisini açamıyor (giriş sayfasına yönleniyor). |
| 2026-10-29 | İçe aktarma işi **askıya alındı**; öncelik harita ve hızlı ekleme. |
| 2026-10-29 | Harita **Google Maps gibi çalışır** ama Apple Haritalar üzerine kuruludur (Google Maps SDK kredi kartlı Google Cloud hesabı istiyor). Eklenen yerler haritada **türünün renk ve simgesiyle** görünür (müze, kafe, tapınak, yemek, bar, konaklama...). |
| 2026-10-29 | Hızlı ekleme (Polarsteps'teki "Add a spot" gibi) **ücretsiz Apple Haritalar verisi** ve Wikipedia ile yapılır; **TripAdvisor kullanılmaz** (ücretsiz API 31 Ağustos 2026'da kapandı, yenisi ömür boyu 1.000 yerden sonra ücretli). Oguz karar kartında "Ücretsiz: Apple Haritalar verisi"ni seçti. |
| 2026-10-29 | Arayüz **basit ve sade** olacak; örnek Oguz'un gönderdiği Polarsteps ekranları (Add a spot listesi, haritada simgeli pinler). |
| 2026-10-29 | Arayüz değişikliklerinde önce **simülatör ekran görüntüleri** Oguz'a gönderilir; Oguz onaylayınca birleştirilir ve TestFlight'a yüklenir. |
| 2026-10-29 | Haritada kayıtlı yere dokununca Google Maps gibi **alttan pencere** açılır: yana kayan fotoğraflar, Wikipedia'dan bilgi ve yazıyı sesli okuyan **Dinle** düğmesi. |
| 2026-10-29 | **Tempo seçimi** (rahat / normal / tempolu) ve **"Günü hafiflet"** şimdilik kaldırıldı; hiçbir yer dışarıda kalmaz. Gün sayısı seçimi duruyor. (Eşit bölme aynı gün kaldırıldı, aşağıya bak.) |
| 2026-10-29 | Şehir planındaki gün listesi **sade** olacak. Bir yere bakarken **harita görünür kalır** ve o yere (yanındaki yerlerle birlikte) yakınlaşır; yer penceresi yarım ekranda kalır. |
| 2026-10-29 | Yerler **günler arasında taşınabilecek**; Oguz tasarımı onaya istedi. Önerilen: yer penceresinde gün düğmeleri, listede basılı tutup sürükleme ya da menüden "n. güne taşı". Ekranlar **tıklanabilir ön izleme** olarak gönderilir. |
| 2026-10-29 | Yerler günlere **otomatik bölünmez**; her yerin gününü **kullanıcı seçer** (eklerken ya da sonradan). Eklerken gün seçilmezse 1. güne gider. Eski gezilerin günleri bir kez sabitlenir, yerler yer değiştirmez. |
| 2026-10-29 | Şehir planında **yalnızca seçili gün** görünür (harita ve liste); gün, listenin üstündeki tek **"1. gün ⌄"** düğmesinden değişir (Gün ekle / Son günü sil de orada). Yer penceresinde gün bilgisi tek düğme: rotadaysa "2. gün ⌄" (taşı, rotadan çıkar), değilse "Rotaya ekle". Sürükleyip bırakma kaldırıldı; listede basılı tutunca "n. güne taşı" menüsü duruyor. |
| 2026-10-29 | Ana sayfada **"Gezim / My travels" başlığı yok**; alttaki gezi paneli içeriği kadar yer kaplar. Oguz bu değişikliklerden sonra **TestFlight'a yüklenmesini** istedi. |
| 2026-10-29 | GitHub'ın gizli depolara verdiği ücretsiz Mac derleme süresi bitti; Oguz karar kartında **depoyu herkese açık yapmayı** seçti (açık depolarda Mac derlemesi ücretsiz). Şifre ve anahtarlar GitHub Secrets'ta kalır. |
| 2026-10-29 | Anlatım (sesli içerik) **hep Türkçe**: önce Türkçe Wikipedia; Türkçe kaynak yoksa İngilizce Wikipedia Türkçeye çevrilip Türkçe sesle okunur (önce iPhone'un ücretsiz çevirisi, olmazsa Gemini/Groq ücretsiz katmanı); kaynak satırında "Türkçeye çevrildi" yazar. |
| 2026-10-29 | Anlatım başlayınca ekranın altında **oynatıcı çubuğu**: duraklat/başlat, 10 sn geri, 10 sn ileri, kapat; sayfa değişince de görünür kalır. |
| 2026-10-29 | Yer penceresindeki fotoğrafa dokununca **tam ekran** açılır; aşağı ya da yukarı itince kapanır. |
| 2026-10-29 | Yol tarifi **Haritalar uygulamasına gitmez**; uygulamanın içinde araba GPS'i gibi sesli yürüyüş rehberi açılır (sıradaki dönüş, mesafe, kalan süre, yoldan çıkınca yeniden rota). |
| 2026-10-29 | Gün düğmesinde **"Tüm yerler"** seçeneği: şehirdeki bütün yerler birlikte (haritada gün numaralı pinler, liste günlere göre). |
| 2026-10-29 | Yer penceresi yarım ekran açılır, yukarı kaydırınca **ekranın %70'ine** çıkar; üstte harita görünür kalır, haritaya dokununca pencere küçülür. |
| 2026-10-29 | Ana sayfada üstteki arama çubuğu kalktı; sağ alttaki siyah düğme **büyüteç** oldu ve doğrudan "Yer ekle"yi (haritadaki şehir için) açar. |
| 2026-10-29 | Şehir planı listesinde (gün ve "Tüm yerler") her yerin solunda **fotoğrafı** (köşesinde tür simgesi), yanında tür ve ad; Polarsteps "Add a spot" gibi. |
| 2026-10-29 | Yol tarifindeki rota çizgisi **yarı saydam**; altındaki harita ayrıntısı görünür. |
| 2026-10-29 | Gezilerde **gerçek tarih yok**, yalnızca gün sayısı: şehirler sırayla "1-3. gün, 4-5. gün" diye görünür (Oguz karar kartında "Yalnızca gün sayısı"nı seçti). |
| 2026-10-29 | Polarsteps gibi **çok şehirli gezi**: geziye sırayla şehir eklenir (ör. İstanbul → Ankara); şehir kartında gün −/+, aralarında araba süresi ya da uçuş; "Ekle" menüsünden yer, konaklama, uçuş, sonrasına şehir. Uçuş ve konaklama yalnızca plana not, rezervasyon yok. |
| 2026-10-29 | **Keşfet sekmesi** (Oguz istedi): şehir/ülke arama, kıta → ülke → şehir gezinme, şehir rehberi ve "Plana ekle"; harita sekmesinin adı "Harita" oldu. İçerik otomatik ve kaynaklı (Wikipedia, Wikivoyage; ücretsiz, CC BY-SA), Türkçeye çevrilir; manuel küratörlük, kullanıcı içeriği, puanlama yok. 2026-10-23'teki "kendi keşif platformu kapsam dışı" kararı yalnızca bu kadarıyla açıldı. |
| 2026-10-29 | Dinleme arayüzü sade: "Dinle" kartı süreyi gösterir, çalarken kartın kendisi oynatıcı olur (10 sn geri/ileri, duraklat, dokunulunca sarılan çizgi, geçen/kalan süre); alttaki çubukta ad, süre, düğmeler; aşağı itince kapanır. Oguz bu değişikliklerden sonra **TestFlight'a yüklenmesini** istedi. |
| 2026-10-29 | Alttaki paneller (ana sayfadaki Gezilerim/Kayıtlarım, şehir planındaki "1. gün" listesi, gezi sayfası) Google Maps gibi **parmakla yukarı-aşağı kayar**: küçük, yarım, büyük; bırakınca en yakına oturur, tutamağa dokununca büyür. |
| 2026-10-29 | Türkçe çeviri: iPhone'un Türkçe çeviri paketi zaten iniyse iPhone çevirisi; inmemişse **indirme sorulmaz** (soru penceresi yer penceresinin arkasında kalıp yazıyı bekletiyordu), doğrudan Gemini/Groq ücretsiz katmanı. |
| 2026-10-29 | Oguz hataları ve gerçek deneyimi telefonda görmek için **son sürümün TestFlight'a gönderilmesini** istedi (yeni şehir ekleme ve Keşfet dahil). |

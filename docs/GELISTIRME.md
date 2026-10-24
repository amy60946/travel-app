# Geliştirme ve telefona kurma rehberi

Bu dosya, uygulamanın nasıl derlendiğini ve Oguz'un telefonuna nasıl
kurulduğunu adım adım anlatır. Teknik ayrıntılar en altta.

## Nasıl çalışıyor (kısaca)

1. Claude kodu yazar ve bir **PR** (değişiklik önerisi) açar.
2. GitHub, kendi Mac bilgisayarlarında uygulamayı otomatik **derler**
   (koddan çalışan uygulama dosyası üretir) ve **testleri** çalıştırır.
   Senin Mac'in olması gerekmez.
3. Sonuçta `.ipa` adlı bir dosya çıkar; bu, iPhone uygulama dosyasıdır.
4. Bu dosyayı ücretsiz yolla kendi iPhone'una kurarsın.

## Derlenmiş uygulamayı indirme

1. GitHub'da depoya gir → üstte **Actions** sekmesi.
2. Soldan **iOS** → listedeki en üstteki yeşil tikli çalışmaya tıkla.
3. Sayfanın altında **Artifacts** bölümünde **TravelApp-imzasiz-ipa**'ya
   tıkla. Bir `.zip` iner; içinden `TravelApp-imzasiz.ipa` çıkar.
4. Dosya 7 gün saklanır; sonra yeni bir derleme gerekir.

## TestFlight kurulmadan önce: iPhone'a elle kurma (Sideloadly)

Sideloadly, Apple hesabınla uygulamayı imzalayıp telefona kuran
ücretsiz bir programdır. Oguz Mac kullanıyor; aşağıdaki adımlar Mac'e
göredir.

1. Bilgisayara **Sideloadly**'yi kur: sideloadly.io → *Download*.
   - Açarken "geliştiricisi doğrulanamadı" uyarısı çıkarsa: **Sistem
     Ayarları → Gizlilik ve Güvenlik** → aşağıda *Yine de Aç*.
2. iPhone'u kabloyla bilgisayara tak; telefonda **"Bu bilgisayara güven"**
   sorusuna *Güven* de.
3. Sideloadly'yi aç → `.ipa` dosyasını pencereye sürükle → **Apple ID**
   kutusuna Apple e-postanı yaz → **Start**. Şifreni Sideloadly sorar;
   bu şifre yalnızca Apple'a gider, sohbete asla yazma.
   - İstersen bu iş için ayrı, ücretsiz bir Apple ID açabilirsin; ana
     hesabını üçüncü taraf programa vermemiş olursun.
4. iPhone'da: **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu** →
   aç (telefon yeniden başlar).
5. iPhone'da: **Ayarlar → Genel → VPN ve Cihaz Yönetimi** → Apple
   ID'ne dokun → **Güven**.
6. Uygulama ana ekranda. **7 gün** sonra açılmaz hale gelir; aynı
   adımlarla yeniden kur (Sideloadly bunu otomatik de yapabilir).

## TestFlight kurulumu (bir kez yapılır)

TestFlight, Apple'ın test uygulamasıdır: yeni sürümler telefonuna
kendiliğinden gelir ve 7 gün sınırı yoktur. Oguz'un mevcut Apple
Developer hesabı kullanılır. Hiçbir bilgiyi sohbete yapıştırma; hepsi
Apple'ın ve GitHub'ın kendi sayfalarına girilir.

**1. Uygulama kimliğini kaydet**
developer.apple.com/account → **Certificates, IDs & Profiles** → soldan
**Identifiers** → mavi **(+)** → **App IDs** → *Continue* → **App** →
*Continue* → *Description*: `TravelApp`, *Bundle ID*: **Explicit** ve
`io.travelapp.ios` → *Continue* → **Register**.

**2. App Store Connect'te uygulamayı oluştur**
appstoreconnect.apple.com → **Apps** → sol üstte **(+)** → **New App** →
*Platforms*: iOS; *Name*: App Store'da görünecek ad (başkası almışsa
"TravelApp Rehber" gibi bir ad dene; sonra değiştirilebilir); *Primary
Language*: Turkish; *Bundle ID*: listeden `io.travelapp.ios`;
*SKU*: `travelapp`; *User Access*: Full Access → **Create**.

**3. API anahtarı oluştur** (GitHub'ın senin adına yükleme yapabilmesi için)
App Store Connect → **Users and Access** → üstte **Integrations** →
soldan **App Store Connect API** → **Team Keys** (ilk kez giriyorsan
önce *Request Access* çıkar, onayla) → **(+)** → *Name*: `GitHub`,
*Access*: **Admin** → **Generate**.
- Satırdaki **Download** ile `.p8` dosyasını indir. **Bu dosya yalnızca
  bir kez indirilebilir.**
- Aynı sayfada iki bilgiyi gör: tablonun üstünde **Issuer ID**,
  anahtarın satırında **Key ID**.

**4. Team ID'yi bul**
developer.apple.com/account → aşağıda **Membership details** →
**Team ID**.

**5. Dört bilgiyi GitHub Secrets'a gir**
GitHub'da depo → üstte **Settings** → soldan **Secrets and variables** →
**Actions** → **New repository secret**. Her biri için *Name* ve
*Secret* kutusunu doldurup **Add secret**:

| Name | Secret kutusuna ne girilecek |
|---|---|
| `ASC_KEY_ID` | 3. adımdaki Key ID |
| `ASC_ISSUER_ID` | 3. adımdaki Issuer ID |
| `APPLE_TEAM_ID` | 4. adımdaki Team ID |
| `ASC_KEY_P8` | `.p8` dosyasının içeriğinin tamamı: Finder → İndirilenler → `AuthKey_….p8` dosyasına sağ tık → *Birlikte Aç* → *TextEdit* → Cmd+A, Cmd+C → kutuya yapıştır (BEGIN ve END satırları dahil) |

Sonra `.p8` dosyasını güvenli bir yere taşı ya da sil.

**6. İlk yüklemeyi başlat**
GitHub'da depo → **Actions** → soldan **TestFlight** → sağda **Run
workflow** → yeşil **Run workflow**. 5-10 dakika sürer. Yeşil tik
gelince App Store Connect → uygulaman → **TestFlight** sekmesinde sürüm
önce "Processing" görünür, 10-30 dakika içinde hazır olur.

**7. Kendini test eden olarak ekle**
App Store Connect → uygulaman → **TestFlight** → solda **Internal
Testing** yanındaki **(+)** → grup adı `Ben` → kendi hesabını ekle.
iPhone'da App Store'dan **TestFlight** uygulamasını indir, aynı Apple
hesabıyla gir → TravelApp görünür → **Yükle**.

Bundan sonra her yeni sürüm için yalnızca 6. adımı tekrarlaman yeterli.

## Ücretsiz kotalar

- Depo özel (private) olduğu için GitHub'ın ücretsiz Actions kotası
  ayda 2.000 dakikadır; Mac bilgisayarlar 10 kat sayıldığından bu
  yaklaşık **200 Mac dakikası** eder (bir derleme ~5-10 dk, ayda ~20-40
  derleme). Kota dolarsa derlemeler ay sonuna kadar durur; GitHub'da
  harcama limiti varsayılan olarak 0 olduğu için **ücret çıkmaz**.
- Derleme yalnızca `ios/` klasörü değişince çalışır; doküman
  değişiklikleri kota harcamaz.

## Teknik ayrıntılar (Claude ve geliştiriciler için)

- Kod: `ios/` — Swift + SwiftUI, iOS 17+, yalnızca iPhone.
- Xcode projesi elle tutulmaz; `ios/project.yml`'den
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile üretilir
  (`cd ios && xcodegen generate`).
- Derleme işi: `.github/workflows/ios.yml` — simülatörde test, sonra
  imzasız `.ipa` üretip artifact olarak yükler.
- TestFlight işi: `.github/workflows/testflight.yml` — elle başlatılır;
  App Store Connect API anahtarıyla otomatik imzalar (`-allowProvisioningUpdates`),
  derleme numarası olarak çalışma numarasını kullanır, `ios/ExportOptions.plist`
  ile doğrudan yükler.
- Paket kimliği (bundle id): `io.travelapp.ios`.
- Dil: geliştirme dili Türkçe; İngilizce çeviriler
  `ios/TravelApp/en.lproj/Localizable.strings`.

## Yapay zekâ anahtarları (isteğe bağlı, ücretsiz)

Fotoğraftan ve kopyalanan yazıdan yer bulma, Google Gemini ve Groq'un
ücretsiz katmanlarını birlikte kullanır. İkisi de kredi kartı istemez.
Anahtarı olmayan servis kapalı kalır; uygulama yine çalışır.

1. **Gemini:** aistudio.google.com → Google hesabınla gir → sol üstte
   *Get API key* → *Create API key* → anahtarı kopyala.
2. **Groq:** console.groq.com → hesap aç → sol menüde *API Keys* →
   *Create API Key* → bir ad ver → anahtarı kopyala.
3. GitHub'da depoya gir → üstte *Settings* → soldan *Secrets and
   variables* → *Actions* → *New repository secret*:
   - Name: `GEMINI_API_KEY`, Secret: Gemini anahtarı → *Add secret*
   - Name: `GROQ_API_KEY`, Secret: Groq anahtarı → *Add secret*

Anahtarlar bir sonraki TestFlight yüklemesinde uygulamaya girer.
Anahtarı sohbete yapıştırma.

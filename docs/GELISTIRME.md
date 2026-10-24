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

## TestFlight bağlanana kadar: iPhone'a elle kurma (Sideloadly)

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

## TestFlight (sonraki adım)

TestFlight, Apple'ın test dağıtım uygulamasıdır; güncellemeler telefona
kendiliğinden gelir, 90 gün geçerlidir ve başkalarını da davet
edebilirsin. **Apple Developer Program** üyeliği gerektirir; Oguz'un
mevcut hesabı var. Bağlarken şu adımlar gelecek (Claude ayrıntılı
anlatacak): App Store Connect'te uygulama kaydı, bir API
anahtarı oluşturup GitHub Secrets'a girmek, derleme işine TestFlight'a
yükleme adımını eklemek.

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
- Paket kimliği (bundle id): `io.github.amy60946.travelapp`.
- Dil: geliştirme dili Türkçe; İngilizce çeviriler
  `ios/TravelApp/en.lproj/Localizable.strings`.

import CoreLocation
import Foundation

/// Keşfet'teki ülke: ISO kodu ve İngilizce Wikipedia / Wikivoyage başlığı.
/// Ekranda telefonun dilindeki adı görünür ("Japonya").
struct Country: Identifiable, Hashable {
    let code: String
    let title: String

    var id: String { code }
    var name: String { Locale.current.localizedString(forRegionCode: code) ?? title }
    var flag: String { Country.flag(code) }

    /// "TR" → 🇹🇷
    static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }

    /// Bütün ülkeler (Türkiye hem Avrupa'da hem Asya'da; bir kez).
    static let all: [Country] = {
        var seen = Set<String>()
        return Continent.all.flatMap(\.countries).filter { seen.insert($0.code).inserted }
    }()

    static func find(_ code: String) -> Country? {
        all.first { $0.code == code.uppercased() }
    }

    /// Aramaya uyan ülkeler: adının (ya da İngilizce adının) bir kelimesi yazılanla başlıyor.
    static func matching(_ text: String) -> [Country] {
        let query = fold(text)
        guard !query.isEmpty else { return [] }
        return all.filter { country in
            [country.name, country.title].contains { name in
                let folded = fold(name)
                return folded.hasPrefix(query) || folded.split(separator: " ").contains { $0.hasPrefix(query) }
            }
        }
        .sorted { $0.name < $1.name }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Keşfet'teki kıta: kapak fotoğrafı (Wikipedia'daki ünlü bir yerin
/// fotoğrafı), haritada nereye bakılacağı ve ülkeleri.
struct Continent: Identifiable, Hashable {
    let id: String
    /// Kapak fotoğrafının alınacağı İngilizce Wikipedia sayfası.
    let photoTitle: String
    let latitude: Double
    let longitude: Double
    /// Haritanın yüksekliği (metre); kıtanın tamamı görünsün.
    let distance: Double
    let countries: [Country]

    var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var name: String {
        switch id {
        case "europe": String(localized: "Avrupa")
        case "asia": String(localized: "Asya")
        case "africa": String(localized: "Afrika")
        case "northAmerica": String(localized: "Kuzey Amerika")
        case "southAmerica": String(localized: "Güney Amerika")
        default: String(localized: "Okyanusya")
        }
    }

    static func find(_ id: String) -> Continent? { all.first { $0.id == id } }

    /// Ülkenin kıtası (Türkiye için Avrupa).
    static func of(_ code: String) -> Continent? {
        all.first { $0.countries.contains { $0.code == code } }
    }

    static let all: [Continent] = [
        Continent(id: "europe", photoTitle: "Eiffel Tower", latitude: 50, longitude: 15, distance: 9_000_000,
                  countries: list("""
                  AL Albania|AD Andorra|AT Austria|BY Belarus|BE Belgium|BA Bosnia and Herzegovina|BG Bulgaria|\
                  HR Croatia|CY Cyprus|CZ Czech Republic|DK Denmark|EE Estonia|FI Finland|FR France|DE Germany|\
                  GR Greece|HU Hungary|IS Iceland|IE Ireland|IT Italy|XK Kosovo|LV Latvia|LI Liechtenstein|\
                  LT Lithuania|LU Luxembourg|MT Malta|MD Moldova|MC Monaco|ME Montenegro|NL Netherlands|\
                  MK North Macedonia|NO Norway|PL Poland|PT Portugal|RO Romania|RU Russia|SM San Marino|RS Serbia|\
                  SK Slovakia|SI Slovenia|ES Spain|SE Sweden|CH Switzerland|TR Turkey|UA Ukraine|\
                  GB United Kingdom|VA Vatican City
                  """)),
        Continent(id: "asia", photoTitle: "Mount Fuji", latitude: 30, longitude: 90, distance: 14_000_000,
                  countries: list("""
                  AF Afghanistan|AM Armenia|AZ Azerbaijan|BH Bahrain|BD Bangladesh|BT Bhutan|BN Brunei|\
                  KH Cambodia|CN China|GE Georgia (country)|HK Hong Kong|IN India|ID Indonesia|IR Iran|IQ Iraq|\
                  IL Israel|JP Japan|JO Jordan|KZ Kazakhstan|KW Kuwait|KG Kyrgyzstan|LA Laos|LB Lebanon|MO Macau|\
                  MY Malaysia|MV Maldives|MN Mongolia|MM Myanmar|NP Nepal|KP North Korea|OM Oman|PK Pakistan|\
                  PS Palestinian territories|PH Philippines|QA Qatar|SA Saudi Arabia|SG Singapore|KR South Korea|\
                  LK Sri Lanka|SY Syria|TW Taiwan|TJ Tajikistan|TH Thailand|TL East Timor|TR Turkey|\
                  TM Turkmenistan|AE United Arab Emirates|UZ Uzbekistan|VN Vietnam|YE Yemen
                  """)),
        Continent(id: "africa", photoTitle: "Victoria Falls", latitude: 2, longitude: 18, distance: 13_000_000,
                  countries: list("""
                  DZ Algeria|AO Angola|BJ Benin|BW Botswana|BF Burkina Faso|BI Burundi|CV Cape Verde|CM Cameroon|\
                  CF Central African Republic|TD Chad|KM Comoros|CD Democratic Republic of the Congo|\
                  CG Republic of the Congo|CI Ivory Coast|DJ Djibouti|EG Egypt|GQ Equatorial Guinea|ER Eritrea|\
                  SZ Eswatini|ET Ethiopia|GA Gabon|GM The Gambia|GH Ghana|GN Guinea|GW Guinea-Bissau|KE Kenya|\
                  LS Lesotho|LR Liberia|LY Libya|MG Madagascar|MW Malawi|ML Mali|MR Mauritania|MU Mauritius|\
                  MA Morocco|MZ Mozambique|NA Namibia|NE Niger|NG Nigeria|RW Rwanda|ST São Tomé and Príncipe|\
                  SN Senegal|SC Seychelles|SL Sierra Leone|SO Somalia|ZA South Africa|SS South Sudan|SD Sudan|\
                  TZ Tanzania|TG Togo|TN Tunisia|UG Uganda|ZM Zambia|ZW Zimbabwe
                  """)),
        Continent(id: "northAmerica", photoTitle: "Grand Canyon", latitude: 38, longitude: -95, distance: 13_000_000,
                  countries: list("""
                  AG Antigua and Barbuda|BS The Bahamas|BB Barbados|BZ Belize|CA Canada|CR Costa Rica|CU Cuba|\
                  DM Dominica|DO Dominican Republic|SV El Salvador|GL Greenland|GD Grenada|GT Guatemala|HT Haiti|\
                  HN Honduras|JM Jamaica|MX Mexico|NI Nicaragua|PA Panama|PR Puerto Rico|\
                  KN Saint Kitts and Nevis|LC Saint Lucia|VC Saint Vincent and the Grenadines|\
                  TT Trinidad and Tobago|US United States
                  """)),
        Continent(id: "southAmerica", photoTitle: "Machu Picchu", latitude: -20, longitude: -60, distance: 11_000_000,
                  countries: list("""
                  AR Argentina|BO Bolivia|BR Brazil|CL Chile|CO Colombia|EC Ecuador|GY Guyana|PY Paraguay|PE Peru|\
                  SR Suriname|UY Uruguay|VE Venezuela
                  """)),
        Continent(id: "oceania", photoTitle: "Sydney Opera House", latitude: -18, longitude: 155, distance: 12_000_000,
                  countries: list("""
                  AU Australia|FJ Fiji|PF French Polynesia|KI Kiribati|MH Marshall Islands|\
                  FM Federated States of Micronesia|NR Nauru|NC New Caledonia|NZ New Zealand|PW Palau|\
                  PG Papua New Guinea|WS Samoa|SB Solomon Islands|TO Tonga|TV Tuvalu|VU Vanuatu
                  """)),
    ]

    /// "JP Japan|KR South Korea" → ülkeler.
    private static func list(_ text: String) -> [Country] {
        text.split(separator: "|").compactMap { item in
            let parts = item.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Country(code: String(parts[0]), title: String(parts[1]))
        }
    }
}

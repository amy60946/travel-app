import CoreLocation
import Foundation

/// Bir gezi (Polarsteps'teki gibi): sırayla şehirler. Her şehrin gün sayısı
/// o şehrin planındadır (`Trip.days`); tarih yok (2026-10-29), şehirler
/// "1-3. gün, 4-5. gün" diye sırayla görünür. Şehre uçakla gelinişi ve
/// şehirdeki konaklama plana not olarak eklenir; rezervasyon yok.
struct Journey: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var stops: [Destination]
}

/// Gezideki bir şehir.
struct Destination: Identifiable, Codable, Hashable {
    var id = UUID()
    var city: String
    /// Ülke kodu (TR, JP...); bayrak için. Bilinmiyorsa nil.
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    /// İngilizce Wikipedia / Wikivoyage başlığı (fotoğraf ve rehber için).
    var englishTitle: String?
    /// Bu şehre uçakla gelinir; yoksa önceki şehirden yol (araba) süresi gösterilir.
    var flight: Flight?
    var stays: [Stay] = []

    init(city: String, countryCode: String? = nil, latitude: Double, longitude: Double,
         englishTitle: String? = nil) {
        self.city = city
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.englishTitle = englishTitle
    }

    init(_ choice: CityChoice) {
        self.init(city: choice.name, countryCode: choice.countryCode,
                  latitude: choice.latitude, longitude: choice.longitude, englishTitle: choice.englishTitle)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var flag: String? { countryCode.map(Country.flag) }

    /// Fotoğraf ve rehber için aranacak başlık.
    var wikiTitle: String { englishTitle ?? city }
}

/// Şehre uçuş: plana not (nereden, uçuş numarası, kalkış saati); bilet ya da tarih yok.
struct Flight: Codable, Hashable {
    var from = ""
    var number = ""
    var departure = ""
    var note = ""

    /// Kartta görünen kısa yazı: "TK 52 · 10:30".
    var summary: String {
        let parts = [number, departure].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? String(localized: "Uçuş") : parts.joined(separator: " · ")
    }
}

/// Şehirde konaklama (otel, ev...): ad, konum ve gece sayısı.
struct Stay: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double?
    var longitude: Double?
    var nights = 1
}

/// Aramadan, Keşfet'ten ya da kayıtlardan seçilen şehir (geziye eklenmeden önce).
struct CityChoice: Identifiable, Hashable {
    var name: String
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    /// İngilizce Wikipedia / Wikivoyage başlığı; bilinmiyorsa nil.
    var englishTitle: String?

    var id: String { name }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var flag: String? { countryCode.map(Country.flag) }
    var wikiTitle: String { englishTitle ?? name }
}

extension Journey {
    /// Her şehrin gün aralığı: ilk şehir 1-3, sonraki 4-5 gibi.
    static func dayRanges(days: [Int]) -> [ClosedRange<Int>] {
        var start = 1
        return days.map { count in
            let range = start...(start + max(count, 1) - 1)
            start = range.upperBound + 1
            return range
        }
    }

    /// "1-3. gün" ya da tek günse "4. gün".
    static func dayText(_ range: ClosedRange<Int>) -> String {
        range.count == 1
            ? String(localized: "\(range.lowerBound). gün")
            : String(localized: "\(range.lowerBound)-\(range.upperBound). gün")
    }

    /// Kısa ad: şehirler "Tokyo, Kyoto, Osaka" (üçten fazlaysa "+2").
    static func defaultName(for cities: [String]) -> String {
        guard cities.count > 3 else { return cities.joined(separator: ", ") }
        return cities.prefix(3).joined(separator: ", ") + " +\(cities.count - 3)"
    }
}

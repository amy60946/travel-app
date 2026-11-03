import CoreLocation
import Foundation

/// Geoapify Places (OpenStreetMap verisi; ücretsiz planda günde 3.000
/// istek, kart yok, Oguz'un 2026-11-03 kararı): yakındaki kafe, restoran,
/// park ve manzara noktaları. "Yer ekle"deki "Yakında yemek, kahve ve park"
/// buradan gelir, Google kotası harcanmaz. Lisans gereği listenin altında
/// "Powered by Geoapify" ve OpenStreetMap yazar. Anahtar `GEOAPIFY_API_KEY`
/// (GitHub Secrets); yoksa yemek ve kahve önerileri Google'dan gelir.
@MainActor
final class GeoapifyService {
    static let shared = GeoapifyService()

    struct Spot: Identifiable, Equatable {
        var id: String
        var name: String
        var latitude: Double
        var longitude: Double
        var category: PlaceCategory
        var website: URL?
        var openingHours: String?
        /// OpenStreetMap kaydının Wikidata bağlantısı varsa bilinen bir yerdir.
        var wikidata: String?

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

        /// OSM'de okunma sayısı yok; kaydın ne kadar dolu olduğu bilinirliğin
        /// yerine geçer (Wikidata bağlantısı, web sitesi, açılış saati).
        var prominence: Double {
            0.25 + (wikidata == nil ? 0 : 0.4) + (website == nil ? 0 : 0.2) + (openingHours == nil ? 0 : 0.15)
        }
    }

    static let apiKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GeoapifyAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }()

    static var isConfigured: Bool { apiKey != nil }

    private var cache: [String: [Spot]] = [:]

    /// Bir noktanın çevresindeki yerler; `food` ise restoran ve kafeler de.
    func nearby(_ center: CLLocationCoordinate2D, radius: Int = 900, food: Bool) async -> [Spot] {
        let key = "\(food)|\((center.latitude * 500).rounded())|\((center.longitude * 500).rounded())"
        if let cached = cache[key] { return cached }
        guard let apiKey = Self.apiKey, !Self.skipsForScreenshot, Self.takeAllowance() else { return [] }
        var categories = ["leisure.park", "tourism.attraction.viewpoint"]
        if food { categories = ["catering.restaurant", "catering.cafe"] + categories }
        var components = URLComponents(string: "https://api.geoapify.com/v2/places")!
        components.queryItems = [
            .init(name: "categories", value: categories.joined(separator: ",")),
            .init(name: "filter", value: "circle:\(center.longitude),\(center.latitude),\(radius)"),
            .init(name: "bias", value: "proximity:\(center.longitude),\(center.latitude)"),
            .init(name: "limit", value: "40"),
            .init(name: "lang", value: AppLanguage.current.rawValue),
            .init(name: "apiKey", value: apiKey),
        ]
        guard let url = components.url,
              let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let places = Self.parse(result.0)
        cache[key] = places
        return places
    }

    /// Geoapify'ın GeoJSON cevabı; adı olmayanlar alınmaz.
    nonisolated static func parse(_ data: Data) -> [Spot] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else { return [] }
        return features.compactMap { feature in
            guard let properties = feature["properties"] as? [String: Any],
                  let name = (properties["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let latitude = properties["lat"] as? Double, let longitude = properties["lon"] as? Double else { return nil }
            let raw = (properties["datasource"] as? [String: Any])?["raw"] as? [String: Any]
            let categories = properties["categories"] as? [String] ?? []
            let website = (properties["website"] as? String ?? raw?["website"] as? String).flatMap(URL.init(string:))
            return Spot(id: properties["place_id"] as? String ?? "\(name)|\(latitude)|\(longitude)",
                         name: name, latitude: latitude, longitude: longitude,
                         category: category(categories), website: website,
                         openingHours: properties["opening_hours"] as? String ?? raw?["opening_hours"] as? String,
                         wikidata: raw?["wikidata"] as? String)
        }
    }

    nonisolated static func category(_ categories: [String]) -> PlaceCategory {
        if categories.contains("catering.cafe") { return .cafe }
        if categories.contains(where: { $0.hasPrefix("catering.bar") || $0.hasPrefix("catering.pub") }) { return .bar }
        if categories.contains(where: { $0.hasPrefix("catering") }) { return .food }
        if categories.contains("tourism.attraction.viewpoint") { return .viewpoint }
        if categories.contains(where: { $0.hasPrefix("leisure.park") }) { return .park }
        return .sight
    }

    /// Önerilecekler: bilinirlik × yakınlık (günün en yakın yerine); en çok
    /// 4 yemek/kafe ve 2 park/manzara. `excluded`: zaten rotada olanlar.
    nonisolated static func pick(_ places: [Spot], anchors: [Place],
                                 excluded: (Spot) -> Bool = { _ in false }) -> [Spot] {
        guard !anchors.isEmpty else { return [] }
        var seen: Set<String> = []
        let scored = places.compactMap { place -> (Spot, Double)? in
            guard !excluded(place), seen.insert(place.name.lowercased()).inserted else { return nil }
            let distance = anchors.map { $0.location.distance(from: place.location) }.min() ?? .infinity
            guard distance <= 1200 else { return nil }
            return (place, place.prominence * (0.4 + 0.6 * exp(-distance / 600)))
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
        let food = scored.filter { [.food, .cafe, .bar].contains($0.category) }.prefix(4)
        let outdoors = scored.filter { [.park, .viewpoint].contains($0.category) }.prefix(2)
        return Array(food) + Array(outdoors)
    }

    /// Telefon başına günde en çok 200 istek (ücretsiz plan günde 3.000).
    private static func takeAllowance() -> Bool {
        let key = "geoapify|" + Date().formatted(.iso8601.year().month().day())
        let used = UserDefaults.standard.integer(forKey: key)
        guard used < 200 else { return false }
        UserDefaults.standard.set(used + 1, forKey: key)
        return true
    }

    /// Ekran görüntüsü açılışları (yalnızca geliştirme sürümü) kotayı harcamasın.
    private static var skipsForScreenshot: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "screen") != nil
        #else
        return false
        #endif
    }
}

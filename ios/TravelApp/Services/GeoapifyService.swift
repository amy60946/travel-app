import CoreLocation
import Foundation

/// İki yer arası yürüme (Geoapify, OpenStreetMap yolları).
struct WalkLeg: Codable, Equatable {
    var meters: Double
    /// Geoapify'ın süresi (saniye); yavaş hesaplıyor (Üsküdar'da dakikada ~50 m).
    var seconds: Double
    /// Dakika: yolun uzunluğu, dakikada 80 m (Google'ın yürüyüş hızı ve
    /// uygulamanın geri kalanıyla aynı). Vapurlu yol uzun çıkar, önerilmez.
    var minutes: Double { meters / 80 }
}

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
        // 40 sonuç 2 kredi (her 20 sonuç 1 kredi).
        guard let apiKey = Self.apiKey, !Self.skipsForScreenshot, Self.spend(2) else { return [] }
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
        let places = Self.readable(Self.parse(result.0))
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

    /// Çevrede pek görülmeyen yazıyla girilmiş adlar alınmaz (Kız Kulesi
    /// önünde Arapça adlı bir "manzara" gibi). Latin harfli adlar hep
    /// kalır; Tokyo'da çoğunluk Japonca olduğu için Japonca adlar da kalır.
    nonisolated static func readable(_ spots: [Spot]) -> [Spot] {
        let scripts = spots.map { script(of: $0.name) }
        var counts: [String: Int] = [:]
        for script in scripts { counts[script, default: 0] += 1 }
        let common = counts.max { $0.value < $1.value }?.key
        return zip(spots, scripts).filter { $0.1 == "latin" || $0.1 == common }.map(\.0)
    }

    /// Adın yazısı (kaba): latin, arabic, hebrew, cyrillic, greek, cjk, hangul, thai ya da other.
    nonisolated static func script(of name: String) -> String {
        var found: String?
        for scalar in name.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value
            let script: String
            switch value {
            case 0x41...0x24F, 0x1E00...0x1EFF: return "latin"
            case 0x370...0x3FF: script = "greek"
            case 0x400...0x52F: script = "cyrillic"
            case 0x590...0x5FF: script = "hebrew"
            case 0x600...0x6FF, 0x750...0x77F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: script = "arabic"
            case 0xE00...0xE7F: script = "thai"
            case 0x1100...0x11FF, 0xAC00...0xD7AF: script = "hangul"
            case 0x3000...0x9FFF, 0xFF00...0xFFEF: script = "cjk"
            default: script = "other"
            }
            if found == nil { found = script }
        }
        return found ?? "other"
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

    // MARK: - Yürüme süreleri

    /// Kaynaklardan hedeflere yürüyerek süre ve mesafe (Route Matrix, Oguz'un
    /// 2026-11-03 kararı). `nil`: istek yapılamadı; hücrede `nil`: yol yok.
    func walkingMatrix(sources: [CLLocationCoordinate2D], targets: [CLLocationCoordinate2D]) async -> [[WalkLeg?]]? {
        guard let apiKey = Self.apiKey, !Self.skipsForScreenshot, !sources.isEmpty, !targets.isEmpty,
              sources.count * targets.count <= 1000,
              Self.spend(Self.matrixCredits(sources: sources.count, targets: targets.count)) else { return nil }
        var components = URLComponents(string: "https://api.geoapify.com/v1/routematrix")!
        components.queryItems = [.init(name: "apiKey", value: apiKey)]
        guard let url = components.url else { return nil }
        func points(_ list: [CLLocationCoordinate2D]) -> [[String: Any]] {
            list.map { ["location": [$0.longitude, $0.latitude]] }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "mode": "walk", "sources": points(sources), "targets": points(targets),
        ] as [String: Any])
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.parseMatrix(result.0, sources: sources.count, targets: targets.count)
    }

    /// Geoapify'ın fiyatı: büyük taraf × küçük taraf (en çok 10).
    nonisolated static func matrixCredits(sources: Int, targets: Int) -> Int {
        max(sources, targets) * min(sources, targets, 10)
    }

    /// `sources_to_targets[i][j]`: i. kaynaktan j. hedefe; süre saniye, mesafe metre.
    nonisolated static func parseMatrix(_ data: Data, sources: Int, targets: Int) -> [[WalkLeg?]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["sources_to_targets"] as? [[Any]] else { return nil }
        var matrix = Array(repeating: [WalkLeg?](repeating: nil, count: targets), count: sources)
        for (rowIndex, row) in rows.enumerated() {
            for (cellIndex, value) in row.enumerated() {
                guard let cell = value as? [String: Any] else { continue }
                let i = cell["source_index"] as? Int ?? rowIndex
                let j = cell["target_index"] as? Int ?? cellIndex
                guard matrix.indices.contains(i), matrix[i].indices.contains(j),
                      let meters = (cell["distance"] as? NSNumber)?.doubleValue,
                      let seconds = (cell["time"] as? NSNumber)?.doubleValue else { continue }
                matrix[i][j] = WalkLeg(meters: meters, seconds: seconds)
            }
        }
        return matrix
    }

    // MARK: - Kota

    /// Telefon başına günde en çok 1.000 kredi; ücretsiz planın günde 3.000
    /// kredisi bütün kullanıcılar için ortak.
    static let dailyCredits = 1_000

    static func spend(_ credits: Int) -> Bool {
        let key = "geoapify-credits|" + Date().formatted(.iso8601.year().month().day())
        let used = UserDefaults.standard.integer(forKey: key)
        guard used + credits <= dailyCredits else { return false }
        UserDefaults.standard.set(used + credits, forKey: key)
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

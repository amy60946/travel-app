import CoreLocation
import Foundation

/// Wikipedia okuma izleri: "Buna bakanlar şunlara da baktı" (Oguz'un
/// 2026-11-03 kararı). Wikipedia her ay okurların hangi sayfadan hangisine
/// geçtiğini yayımlar (clickstream, CC0, İngilizce Wikipedia). GitHub
/// Actions bunu ayda bir işler (ios/scripts/reading_trails.py): yalnızca
/// haritada yeri olan sayfalar, birbirine 20 km'den yakın iki yer arası
/// iki yönlü geçişler; dünya 0,5°'lik karelere bölünür ve "okuma-izleri"
/// dalına konur. Uygulama gezilen yerin karesini bir kez indirir, 30 gün
/// saklar; anahtar, hesap ya da kota yok.
///
/// Benzer uygulamalar (Google Maps "İnsanlar şunları da arıyor",
/// Tripadvisor, Wanderlog) bunu kendi kullanıcılarının verisiyle yapıyor;
/// burada milyonlarca Wikipedia okurunun gezintisi kullanılır.
actor ReadingTrails {
    static let shared = ReadingTrails()

    /// Bir yere bakanların baktığı başka bir yer.
    struct Related: Equatable {
        /// İngilizce Wikipedia başlığı.
        var title: String
        var latitude: Double
        var longitude: Double
        /// Ayda iki yönlü geçiş (iki sayfa arasında).
        var together: Int
        /// Ayda kaynak sayfaya gelen okur (yaklaşık).
        var readers: Int

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

        /// 0...1: kaynak sayfanın okurlarının ne kadarı buna da geçiyor.
        /// %0,5 → 0,5; %1,5 → 0,75; %5 → 0,9 (birkaç büyük yer hep 1 olmasın).
        var strength: Double { Self.strength(together: together, readers: readers) }

        static func strength(together: Int, readers: Int) -> Double {
            guard readers > 0, together > 0 else { return 0 }
            let share = Double(together) / Double(readers)
            return share / (share + 0.005)
        }
    }

    /// Bir kare dosyası (betikteki biçim).
    struct Tile: Codable, Equatable {
        var month: String
        var titles: [String]
        var lat: [Double]
        var lon: [Double]
        var readers: [Int]
        /// Karedeki yerin sırası → [birlikte okunan yerin sırası, geçiş].
        var related: [String: [[Int]]]

        func items(for title: String) -> [Related]? {
            guard let index = titles.firstIndex(of: title), let items = related[String(index)] else { return nil }
            let sourceReaders = readers.indices.contains(index) ? readers[index] : 0
            return items.compactMap { item in
                guard item.count == 2, titles.indices.contains(item[0]),
                      lat.indices.contains(item[0]), lon.indices.contains(item[0]) else { return nil }
                let other = item[0]
                return Related(title: titles[other], latitude: lat[other], longitude: lon[other],
                               together: item[1], readers: sourceReaders)
            }
        }
    }

    static let base = URL(string: "https://raw.githubusercontent.com/amy60946/travel-app/okuma-izleri/tiles/")!
    static let tileSize = 0.5
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    /// Bu açılışta okunan kareler; nil: o karede veri yok.
    private var tiles: [String: Tile?] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TravelApp/0.1 (https://github.com/amy60946/travel-app)"]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TravelApp/ReadingTrails", isDirectory: true)

    /// Bu sayfaya bakanların en çok baktığı yerler (çoktan aza). `title`
    /// İngilizce Wikipedia başlığı; konum karenin bulunması için.
    func related(to title: String, latitude: Double, longitude: Double) async -> [Related] {
        guard WikipediaService.localOnly(title) == nil else { return [] }
        for name in Self.tileNames(latitude: latitude, longitude: longitude) {
            if let found = await tile(name)?.items(for: title) { return found }
        }
        return []
    }

    /// Günün yerlerine bakanların baktığı yerler: her yer için en güçlüsü.
    func alsoRead(from places: [Place]) async -> [String: Related] {
        var best: [String: Related] = [:]
        for place in places {
            guard let title = place.wikipediaTitle else { continue }
            for item in await related(to: title, latitude: place.latitude, longitude: place.longitude)
            where (best[item.title]?.strength ?? -1) < item.strength {
                best[item.title] = item
            }
        }
        return best
    }

    /// Yerin karesi; kare kenarına 2 km'den yakınsa komşu kareler de (yerin
    /// uygulamadaki konumu Wikipedia'dakinden biraz farklı olabilir).
    static func tileNames(latitude: Double, longitude: Double) -> [String] {
        let margin = 0.02
        var names: [String] = []
        for dLat in [0, -margin, margin] {
            for dLon in [0, -margin, margin] {
                let name = tileName(latitude: latitude + dLat, longitude: longitude + dLon)
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    static func tileName(latitude: Double, longitude: Double) -> String {
        let lat = (latitude / tileSize).rounded(.down) * tileSize
        let lon = (longitude / tileSize).rounded(.down) * tileSize
        return String(format: "%.1f_%.1f", locale: Locale(identifier: "en_US_POSIX"), lat + 0, lon + 0)
    }

    private func tile(_ name: String) async -> Tile? {
        if let known = tiles[name] { return known }
        let file = folder.appendingPathComponent("\(name).json")
        let saved = try? Data(contentsOf: file)
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        if let saved, age < Self.maxAge {
            let tile = try? JSONDecoder().decode(Tile.self, from: saved)
            tiles[name] = .some(tile)
            return tile
        }
        guard let result = try? await session.data(from: Self.base.appendingPathComponent("\(name).json")),
              let status = (result.1 as? HTTPURLResponse)?.statusCode else {
            // İnternet yok: eski dosya varsa o.
            return saved.flatMap { try? JSONDecoder().decode(Tile.self, from: $0) }
        }
        let data = result.0
        var tile: Tile?
        if status == 200 { tile = try? JSONDecoder().decode(Tile.self, from: data) }
        if status == 200 || status == 404 {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Verisi olmayan kare de saklanır ("-"): her açılışta yeniden sorulmaz.
            try? (tile == nil ? Data("-".utf8) : data).write(to: file, options: .atomic)
            tiles[name] = .some(tile)
        }
        return tile
    }
}

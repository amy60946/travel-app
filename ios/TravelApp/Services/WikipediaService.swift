import Foundation

/// Wikipedia'dan (ücretsiz, CC BY-SA) açıklama, fotoğraf ve popüler
/// yerler. Her metin kaynağıyla birlikte gösterilir.
actor WikipediaService {
    static let shared = WikipediaService()

    struct Summary: Equatable, Codable {
        var title: String
        var extract: String
        var pageURL: URL?
        var thumbnailURL: URL?
        var language: String
        /// Türkçe sayfa yoksa İngilizceden çevrildi ("en").
        var translatedFrom: String? = nil
    }

    struct PopularPlace: Identifiable, Equatable {
        var title: String
        var latitude: Double
        var longitude: Double
        var monthlyViews: Int
        var thumbnailURL: URL?
        var id: String { title }
    }

    /// Anlatım dili: telefonun dili ne olursa olsun Türkçe (Oguz, 2026-10-29).
    static let narrationLanguage = "tr"

    /// Bir kez okunan özet ve fotoğraf listesi telefonda saklanır; internetsiz de açılır.
    private let summaries = DiskCache<Summary>(name: "wikipedia-summaries")
    private let photoLists = DiskCache<[URL]>(name: "wikipedia-photos")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TravelApp/0.1 (https://github.com/amy60946/travel-app)"]
        return URLSession(configuration: config)
    }()

    /// İngilizce başlıktan, istenen dilde özet. O dilde sayfa yoksa
    /// İngilizcesi Türkçeye çevrilir; çeviri olmazsa İngilizcesi döner
    /// (saklanmaz, sonra yeniden denenir).
    func summary(englishTitle: String, language: String = WikipediaService.narrationLanguage) async -> Summary? {
        let key = "\(language)|\(englishTitle)"
        if let cached = summaries[key] { return cached }
        if language != "en", let local = try? await localTitle(for: englishTitle, language: language),
           let result = try? await fetchSummary(title: local, language: language) {
            summaries[key] = result
            return result
        }
        guard let english = await englishSummary(englishTitle) else { return nil }
        guard language == "tr", let translated = await Translator.shared.toTurkish(english.extract) else {
            return english
        }
        var result = english
        result.extract = translated
        result.language = "tr"
        result.translatedFrom = "en"
        summaries[key] = result
        return result
    }

    /// Sayfanın küçük fotoğrafı (İngilizce özetten; çeviri gerekmez).
    func thumbnailURL(englishTitle: String) async -> URL? {
        await englishSummary(englishTitle)?.thumbnailURL
    }

    private func englishSummary(_ title: String) async -> Summary? {
        let key = "en|\(title)"
        if let cached = summaries[key] { return cached }
        guard let result = try? await fetchSummary(title: title, language: "en") else { return nil }
        summaries[key] = result
        return result
    }

    /// Bir noktanın 10 km çevresindeki Wikipedia sayfaları, son 30 günde
    /// en çok okunandan aza.
    func popularPlaces(latitude: Double, longitude: Double, limit: Int = 15) async throws -> [PopularPlace] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "geosearch"),
            .init(name: "ggscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "ggsradius", value: "10000"),
            .init(name: "ggslimit", value: "50"),
            .init(name: "prop", value: "coordinates|pageviews|pageimages"),
            .init(name: "pithumbsize", value: "300"),
            .init(name: "pvipdays", value: "30"),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page] }
            struct Page: Decodable {
                struct Coordinate: Decodable { var lat: Double; var lon: Double }
                struct Thumbnail: Decodable { var source: URL }
                var title: String
                var coordinates: [Coordinate]?
                var pageviews: [String: Int?]?
                var thumbnail: Thumbnail?
            }
            var query: Query?
        }
        let (data, _) = try await session.data(from: components.url!)
        let pages = try JSONDecoder().decode(Response.self, from: data).query?.pages ?? []
        return pages
            .compactMap { page -> PopularPlace? in
                guard let c = page.coordinates?.first, Self.isSight(page.title) else { return nil }
                let views = page.pageviews?.values.compactMap { $0 }.reduce(0, +) ?? 0
                return PopularPlace(title: page.title, latitude: c.lat, longitude: c.lon,
                                    monthlyViews: views, thumbnailURL: page.thumbnail?.source)
            }
            .sorted { $0.monthlyViews > $1.monthlyViews }
            .prefix(limit)
            .map { $0 }
    }

    /// Sayfadaki fotoğraflar (yana kaydırılan galeri için), en çok 10.
    func photos(englishTitle: String) async -> [URL] {
        if let cached = photoLists[englishTitle] { return cached }
        struct Response: Decodable {
            struct Item: Decodable {
                struct Source: Decodable { var src: String }
                var title: String?
                var type: String
                var showInGallery: Bool?
                var srcset: [Source]?
            }
            var items: [Item]
        }
        guard let url = Self.restURL(language: "en", endpoint: "media-list", title: englishTitle),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let items = try? JSONDecoder().decode(Response.self, from: data).items
        else { return [] }
        let photos = items
            .filter { $0.type == "image" && $0.showInGallery != false }
            .filter { !($0.title ?? "").lowercased().hasSuffix(".svg") }
            .compactMap { $0.srcset?.first?.src }
            .compactMap { URL(string: $0.hasPrefix("//") ? "https:" + $0 : $0) }
        let result = Array(photos.prefix(10))
        if !result.isEmpty { photoLists[englishTitle] = result }
        return result
    }

    /// Wikipedia sayfası olmayan yerler (kafe, restoran...) için yakında
    /// çekilmiş fotoğraflar (Wikimedia Commons, 150 m içinde).
    func nearbyPhotos(latitude: Double, longitude: Double) async -> [URL] {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "geosearch"),
            .init(name: "ggsnamespace", value: "6"),
            .init(name: "ggscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "ggsradius", value: "150"),
            .init(name: "ggslimit", value: "10"),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|mime"),
            .init(name: "iiurlwidth", value: "640"),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page] }
            struct Page: Decodable {
                struct Info: Decodable { var thumburl: URL?; var mime: String? }
                var imageinfo: [Info]?
            }
            var query: Query?
        }
        guard let (data, _) = try? await session.data(from: components.url!),
              let pages = try? JSONDecoder().decode(Response.self, from: data).query?.pages
        else { return [] }
        return pages
            .compactMap(\.imageinfo?.first)
            .filter { $0.mime == "image/jpeg" || $0.mime == "image/png" }
            .compactMap(\.thumburl)
    }

    /// Kayıtlı yerin İngilizce Wikipedia sayfası: 300 m içindeki sayfalardan
    /// adı yerin adıyla örtüşen ("Meiji Tapınağı" → "Meiji Shrine").
    /// Emin olunamazsa nil (yanlış yazı göstermektense hiç göstermemek).
    func findArticle(name: String, city: String, latitude: Double, longitude: Double) async -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "list", value: "geosearch"),
            .init(name: "gscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "gsradius", value: "300"),
            .init(name: "gslimit", value: "20"),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var geosearch: [Page] }
            struct Page: Decodable { var title: String }
            var query: Query?
        }
        guard let (data, _) = try? await session.data(from: components.url!),
              let pages = try? JSONDecoder().decode(Response.self, from: data).query?.geosearch
        else { return nil }
        // Önce adı aynı ya da içeren sayfa, yoksa ortak kelimesi olan.
        let titles = pages.map(\.title)
        return titles.first { Self.matchesStrongly(title: $0, name: name) }
            ?? titles.first { Self.matches(title: $0, name: name, city: city) }
    }

    /// Sayfa başlığı yerin adıyla örtüşüyor mu: biri ötekini içeriyor ya da
    /// genel olmayan (tapınak, park, şehir adı dışında) bir kelime ortak ve
    /// türleri çelişmiyor ("Ueno Station" ile "Ueno Parkı" eşleşmez).
    static func matches(title: String, name: String, city: String) -> Bool {
        if matchesStrongly(title: title, name: name) { return true }
        let a = words(fold(title)), b = words(fold(name))
        let cityWord = fold(city)
        let kindsA = Set(a.compactMap { kinds[$0] }), kindsB = Set(b.compactMap { kinds[$0] })
        if !kindsA.isEmpty && !kindsB.isEmpty && kindsA.isDisjoint(with: kindsB) { return false }
        let significant = { (words: Set<String>) in
            words.filter { $0.count >= 4 && $0 != cityWord && kinds[$0] == nil && !["the", "national", "art"].contains($0) }
        }
        return !significant(a).isDisjoint(with: significant(b))
    }

    static func matchesStrongly(title: String, name: String) -> Bool {
        let a = fold(title), b = fold(name)
        return a == b || (b.count >= 4 && a.contains(b)) || (a.count >= 4 && b.contains(a))
    }

    /// Yer türü bildiren kelimeler (İngilizce ve Türkçe) ve türleri.
    private static let kinds: [String: String] = [
        "temple": "temple", "shrine": "temple", "tapinagi": "temple", "tapinak": "temple", "mosque": "temple",
        "camii": "temple", "church": "temple", "kilisesi": "temple",
        "park": "park", "parki": "park", "garden": "park", "gardens": "park", "bahcesi": "park",
        "tower": "tower", "kulesi": "tower", "museum": "museum", "muzesi": "museum",
        "palace": "palace", "sarayi": "palace", "station": "station", "istasyonu": "station",
        "market": "market", "bazaar": "market", "carsisi": "market", "bridge": "bridge", "koprusu": "bridge",
        "castle": "castle", "hotel": "hotel", "cafe": "cafe", "restaurant": "restaurant", "street": "street",
    ]

    private static func words(_ text: String) -> Set<String> {
        Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Gezilecek yer gibi görünmeyen sayfalar (üniversite, istasyon, bakanlık…)
    /// popüler listesine alınmaz.
    static func isSight(_ title: String) -> Bool {
        let lower = title.lowercased()
        let excluded = ["university", "college", "school", "station", "line", "railway", "hospital",
                        "embassy", "ministry", "headquarters", "prefecture", "ward", "district",
                        "company", "corporation", "bank", "court", "police", "office", "airport",
                        "expressway", "highway", "route", "list of", "chongryon", "constituency"]
        return !excluded.contains { lower.contains($0) }
    }

    // MARK: - İstekler

    private func fetchSummary(title: String, language: String) async throws -> Summary? {
        struct Response: Decodable {
            struct Thumbnail: Decodable { var source: URL }
            struct ContentURLs: Decodable {
                struct Page: Decodable { var page: URL }
                var mobile: Page?
            }
            var type: String?
            var title: String
            var extract: String?
            var thumbnail: Thumbnail?
            var content_urls: ContentURLs?
        }
        guard let url = Self.restURL(language: language, endpoint: "summary", title: title) else { return nil }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.type != "disambiguation", let extract = decoded.extract, !extract.isEmpty else { return nil }
        return Summary(title: decoded.title, extract: extract, pageURL: decoded.content_urls?.mobile?.page,
                       thumbnailURL: decoded.thumbnail?.source, language: language)
    }

    /// Wikipedia REST adresi (ör. page/summary/Sensō-ji).
    private static func restURL(language: String, endpoint: String, title: String) -> URL? {
        // Yalnızca ASCII harfler açık kalır; "ō" gibi harfler kodlanır.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.()")
        guard let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/\(endpoint)/\(path)")
    }

    /// İngilizce sayfanın başka dildeki karşılığının başlığı.
    private func localTitle(for englishTitle: String, language: String) async throws -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "langlinks"),
            .init(name: "lllang", value: language),
            .init(name: "redirects", value: "1"),
            .init(name: "titles", value: englishTitle),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page] }
            struct Page: Decodable {
                struct Link: Decodable { var title: String }
                var langlinks: [Link]?
            }
            var query: Query?
        }
        let (data, _) = try await session.data(from: components.url!)
        return try JSONDecoder().decode(Response.self, from: data).query?.pages.first?.langlinks?.first?.title
    }
}

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
    }

    struct PopularPlace: Identifiable, Equatable {
        var title: String
        var latitude: Double
        var longitude: Double
        var monthlyViews: Int
        var thumbnailURL: URL?
        var id: String { title }
    }

    /// Arayüz dili Türkçeyse Türkçe, değilse İngilizce.
    static var preferredLanguage: String {
        Locale.current.language.languageCode?.identifier == "tr" ? "tr" : "en"
    }

    /// Bir kez okunan özet telefonda saklanır; internetsiz de açılır.
    private let summaries = DiskCache<Summary>(name: "wikipedia-summaries")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TravelApp/0.1 (https://github.com/amy60946/travel-app)"]
        return URLSession(configuration: config)
    }()

    /// İngilizce başlıktan, istenen dilde özet. O dilde sayfa yoksa İngilizcesi.
    func summary(englishTitle: String, language: String = WikipediaService.preferredLanguage) async -> Summary? {
        let key = "\(language)|\(englishTitle)"
        if let cached = summaries[key] { return cached }
        var result: Summary?
        if language != "en", let local = try? await localTitle(for: englishTitle, language: language) {
            result = try? await fetchSummary(title: local, language: language)
        }
        if result == nil {
            result = try? await fetchSummary(title: englishTitle, language: "en")
        }
        if let result { summaries[key] = result }
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
                guard let c = page.coordinates?.first else { return nil }
                let views = page.pageviews?.values.compactMap { $0 }.reduce(0, +) ?? 0
                return PopularPlace(title: page.title, latitude: c.lat, longitude: c.lon,
                                    monthlyViews: views, thumbnailURL: page.thumbnail?.source)
            }
            .sorted { $0.monthlyViews > $1.monthlyViews }
            .prefix(limit)
            .map { $0 }
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
        // Yalnızca ASCII harfler açık kalır; "ō" gibi harfler kodlanır.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.()")
        guard let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(path)")
        else { return nil }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.type != "disambiguation", let extract = decoded.extract, !extract.isEmpty else { return nil }
        return Summary(title: decoded.title, extract: extract, pageURL: decoded.content_urls?.mobile?.page,
                       thumbnailURL: decoded.thumbnail?.source, language: language)
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

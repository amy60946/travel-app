import CoreLocation
import Foundation

/// Wikivoyage yer listeleri (ücretsiz, CC BY-SA): gezginlerin yazdığı
/// kısa açıklama, açılış saati ve fiyat (Görülecek, Yapılacak, Yemek,
/// İçecek, Alışveriş). Wikipedia'da sayfası olmayan kafe, restoran, çarşı
/// gibi yerlerde yer penceresinde "Gezgin notu" olarak görünür, yürüyüşte
/// okunur. En kapsamlısı olan İngilizce Wikivoyage kullanılır; uygulama
/// Türkçeyse açıklama Türkçeye çevrilir. Bulunan saklanır.
actor WikivoyageListings {
    static let shared = WikivoyageListings()

    struct Listing: Codable, Equatable {
        /// see, do, eat, drink, buy, sleep
        var kind: String
        var name: String
        var alt: String?
        var latitude: Double?
        var longitude: Double?
        var content: String
        var hours: String?
        var price: String?
        var website: URL?
        /// Listenin bulunduğu Wikivoyage sayfası.
        var article: String
        var language = "en"
        var translatedFrom: String?

        var pageURL: URL? {
            let path = article.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            return path.flatMap { URL(string: "https://en.wikivoyage.org/wiki/\($0)") }
        }
    }

    private let found = DiskCache<Listing>(name: "wikivoyage-listings")
    private var missing: Set<String> = []
    /// Bu açılışta okunan sayfaların listeleri.
    private var articleCache: [String: [Listing]] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TravelApp/0.1 (https://github.com/amy60946/travel-app)"]
        return URLSession(configuration: config)
    }()
    private static let api = "https://en.wikivoyage.org/w/api.php"

    /// Yerin Wikivoyage'daki listesi (adı tutan ve 300 m içinde olan), yoksa nil.
    /// Önce adı (ve İngilizce Wikipedia adı) geçen sayfalar, sonra en yakın
    /// sayfalar aranır: Kız Kulesi'ne en yakın sayfa karşı yakadaki Galata,
    /// listesi ise "Istanbul/Asian Side"da.
    func listing(name: String, englishTitle: String? = nil, latitude: Double, longitude: Double,
                 language: String = WikipediaService.narrationLanguage) async -> Listing? {
        let key = "\(language)|\(name)|\((latitude * 1000).rounded() / 1000)|\((longitude * 1000).rounded() / 1000)"
        if let cached = found[key] { return cached }
        guard !missing.contains(key), !name.isEmpty else { return nil }
        var match: Listing?
        var articles: [String] = []
        var queries = [name]
        if let englishTitle, WikipediaService.localOnly(englishTitle) == nil, englishTitle != name {
            queries.append(englishTitle)
        }
        for query in queries {
            articles += await searchArticles(query)
        }
        articles += await nearbyArticles(latitude: latitude, longitude: longitude)
        var seen: Set<String> = []
        articles = articles.filter { seen.insert($0).inserted }
        for article in articles.prefix(5) {
            let listings = await listings(in: article)
            let best = Self.bestMatch(listings, name: name, latitude: latitude, longitude: longitude)
                ?? englishTitle.flatMap { Self.bestMatch(listings, name: $0, latitude: latitude, longitude: longitude) }
            if let best {
                match = best
                break
            }
        }
        guard var match else {
            missing.insert(key)
            return nil
        }
        if language == "tr", let translated = await Translator.shared.toTurkish(match.content) {
            match.content = translated
            match.language = "tr"
            match.translatedFrom = "en"
        }
        found[key] = match
        return match
    }

    /// Adı geçen Wikivoyage sayfaları (en çok 3).
    private func searchArticles(_ text: String) async -> [String] {
        var components = URLComponents(string: Self.api)!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "list", value: "search"),
            .init(name: "srsearch", value: "\"\(text)\""),
            .init(name: "srnamespace", value: "0"),
            .init(name: "srlimit", value: "3"),
            .init(name: "srprop", value: ""),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var search: [Page] }
            struct Page: Decodable { var title: String }
            var query: Query?
        }
        guard let url = components.url,
              let result = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: result.0) else { return [] }
        return (response.query?.search ?? []).map(\.title)
    }

    /// Yerin çevresindeki Wikivoyage sayfaları (şehir ve semt), en yakını önce.
    private func nearbyArticles(latitude: Double, longitude: Double) async -> [String] {
        var components = URLComponents(string: Self.api)!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "list", value: "geosearch"),
            .init(name: "gscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "gsradius", value: "10000"),
            .init(name: "gslimit", value: "4"),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var geosearch: [Page] }
            struct Page: Decodable { var title: String }
            var query: Query?
        }
        guard let url = components.url,
              let result = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: result.0) else { return [] }
        return (response.query?.geosearch ?? []).map(\.title).prefix(3).map { $0 }
    }

    private func listings(in article: String) async -> [Listing] {
        if let cached = articleCache[article] { return cached }
        var components = URLComponents(string: Self.api)!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "revisions"),
            .init(name: "rvprop", value: "content"),
            .init(name: "rvslots", value: "main"),
            .init(name: "titles", value: article),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page] }
            struct Page: Decodable {
                struct Revision: Decodable {
                    struct Slots: Decodable {
                        struct Main: Decodable { var content: String? }
                        var main: Main
                    }
                    var slots: Slots
                }
                var revisions: [Revision]?
            }
            var query: Query?
        }
        guard let url = components.url,
              let result = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: result.0),
              let text = response.query?.pages.first?.revisions?.first?.slots.main.content else { return [] }
        let listings = Self.parseListings(text, article: article)
        articleCache[article] = listings
        return listings
    }

    // MARK: - Eşleme

    static func bestMatch(_ listings: [Listing], name: String, latitude: Double, longitude: Double) -> Listing? {
        let place = CLLocation(latitude: latitude, longitude: longitude)
        let candidates = listings.compactMap { listing -> (Listing, Double)? in
            guard sameName(listing.name, name) || listing.alt.map({ sameName($0, name) }) == true else { return nil }
            guard let lat = listing.latitude, let lon = listing.longitude else {
                // Konumu olmayan listede ad birebir tutmalı.
                return fold(listing.name) == fold(name) ? (listing, 0) : nil
            }
            let distance = CLLocation(latitude: lat, longitude: lon).distance(from: place)
            return distance <= 300 ? (listing, distance) : nil
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    /// "Omoide Yokocho" ↔ "Omoide Yokochō (Memory Lane)": harf farkları ve
    /// parantezler yok sayılır; biri öbürünün başında geçiyorsa da aynı.
    static func sameName(_ first: String, _ second: String) -> Bool {
        let a = fold(first), b = fold(second)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let shorter = a.count < b.count ? a : b
        let longer = a.count < b.count ? b : a
        return shorter.count >= 5 && longer.hasPrefix(shorter + " ")
    }

    static func fold(_ text: String) -> String {
        let withoutParentheses = text.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
        return withoutParentheses.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Sayfa yazısından listeler

    private static let kinds: Set<String> = ["see", "do", "eat", "drink", "buy", "sleep", "listing"]

    /// `{{see | name=… | lat=… | long=… | content=… }}` gibi şablonlar.
    static func parseListings(_ wikitext: String, article: String) -> [Listing] {
        let text = Array(wikitext)
        var result: [Listing] = []
        var index = 0
        while index + 1 < text.count {
            guard text[index] == "{", text[index + 1] == "{" else {
                index += 1
                continue
            }
            var nameEnd = index + 2
            while nameEnd < text.count, !["|", "}", "\n"].contains(text[nameEnd]) { nameEnd += 1 }
            let name = String(text[(index + 2)..<nameEnd]).trimmingCharacters(in: .whitespaces).lowercased()
            guard kinds.contains(name) else {
                index += 2
                continue
            }
            // Şablonun sonu (iç içe şablonlar sayılarak).
            var depth = 0
            var end = index
            var closed = false
            while end + 1 < text.count {
                if text[end] == "{", text[end + 1] == "{" {
                    depth += 1
                    end += 2
                } else if text[end] == "}", text[end + 1] == "}" {
                    depth -= 1
                    end += 2
                    if depth == 0 {
                        closed = true
                        break
                    }
                } else {
                    end += 1
                }
            }
            guard closed else { break }
            let body = Array(text[nameEnd..<(end - 2)])
            if let listing = listing(name, parameters: parameters(body), article: article) { result.append(listing) }
            index = end
        }
        return result
    }

    private static func listing(_ template: String, parameters: [String: String], article: String) -> Listing? {
        let kind = template == "listing" ? (parameters["type"] ?? "see").lowercased() : template
        guard let name = parameters["name"].map(plain), !name.isEmpty,
              let content = (parameters["content"] ?? parameters["description"]).map(plain), content.count >= 20
        else { return nil }
        func value(_ key: String) -> String? {
            parameters[key].map(plain).flatMap { $0.isEmpty ? nil : $0 }
        }
        return Listing(kind: kind, name: name, alt: value("alt"),
                       latitude: parameters["lat"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) },
                       longitude: parameters["long"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) },
                       content: content, hours: value("hours"), price: value("price"),
                       website: parameters["url"].flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) },
                       article: article)
    }

    /// Üst düzeydeki "|" işaretlerinden bölünmüş "ad=değer" çiftleri.
    private static func parameters(_ body: [Character]) -> [String: String] {
        var parts: [String] = []
        var current = ""
        var braces = 0
        var brackets = 0
        var index = 0
        while index < body.count {
            let character = body[index]
            let next = index + 1 < body.count ? body[index + 1] : nil
            if character == "{", next == "{" { braces += 1; current += "{{"; index += 2; continue }
            if character == "}", next == "}" { braces -= 1; current += "}}"; index += 2; continue }
            if character == "[", next == "[" { brackets += 1; current += "[["; index += 2; continue }
            if character == "]", next == "]" { brackets -= 1; current += "]]"; index += 2; continue }
            if character == "|", braces == 0, brackets == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        parts.append(current)
        var result: [String: String] = [:]
        for part in parts {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    /// Wiki işaretleri temizlenir: [[a|b]] → b, ''eğik'', iç şablonlar, HTML.
    static func plain(_ wiki: String) -> String {
        var text = wiki.replacingOccurrences(of: "<ref[^>]*/>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<ref[^>]*>[\\s\\S]*?</ref>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // İç şablonlar (içten dışa).
        while text.range(of: "\\{\\{[^{}]*\\}\\}", options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: "\\{\\{[^{}]*\\}\\}", with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "\\[\\[(?:[^\\]|]*\\|)?([^\\]]+)\\]\\]", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\[https?://[^\\s\\]]+ ([^\\]]+)\\]", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\[https?://[^\\]]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "'{2,}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

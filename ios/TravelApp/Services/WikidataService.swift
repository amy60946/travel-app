import Foundation

/// Wikidata (ücretsiz, anahtarsız, CC0): yerin kesin bilgileri ve ana
/// fotoğrafı. Yerin Wikipedia sayfasından bulunur; yapım yılı, mimar,
/// mimari üslup, yükseklik, yıllık ziyaretçi, koruma statüsü ve resmi site
/// yer penceresinde "Bilgiler" olarak görünür. Wikipedia sayfasında
/// fotoğraf yoksa Wikidata'daki fotoğraf kullanılır. Bulunan saklanır.
actor WikidataService {
    static let shared = WikidataService()

    struct Facts: Codable, Equatable {
        var id: String
        var description: String?
        /// "1110", "MÖ 410" ya da "1960'lar".
        var built: String?
        var architects: [String] = []
        var styles: [String] = []
        var heritage: [String] = []
        /// Metre.
        var height: Double?
        var visitorsPerYear: Int?
        var website: URL?
        var imageURL: URL?

        var isEmpty: Bool {
            built == nil && architects.isEmpty && styles.isEmpty && heritage.isEmpty
                && height == nil && visitorsPerYear == nil && website == nil
        }
    }

    private let cache = DiskCache<Facts>(name: "wikidata-facts")
    private var missing: Set<String> = []
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TravelApp/0.1 (https://github.com/amy60946/travel-app)"]
        return URLSession(configuration: config)
    }()
    private static let api = "https://www.wikidata.org/w/api.php"

    /// Wikipedia başlığından (İngilizce ya da "tr:Başlık") yerin bilgileri.
    func facts(wikipediaTitle: String, language: String = WikipediaService.narrationLanguage) async -> Facts? {
        let key = "\(language)|\(wikipediaTitle)"
        if let cached = cache[key] { return cached }
        guard !missing.contains(key) else { return nil }
        let site = WikipediaService.localOnly(wikipediaTitle).map { (wiki: "\($0.language)wiki", title: $0.title) }
            ?? (wiki: "enwiki", title: wikipediaTitle)
        guard let entity = await entity(site: site.wiki, title: site.title) else {
            missing.insert(key)
            return nil
        }
        let parsed = Self.parse(entity, language: language)
        var facts = parsed.0
        let linked = parsed.1
        if !linked.isEmpty {
            let labels = await labels(Array(Set(linked.values.flatMap { $0 })), language: language)
            func names(_ property: String) -> [String] { (linked[property] ?? []).compactMap { labels[$0] } }
            facts.architects = names("P84")
            facts.styles = names("P149")
            facts.heritage = names("P1435")
        }
        cache[key] = facts
        return facts
    }

    private func entity(site: String, title: String) async -> [String: Any]? {
        var components = URLComponents(string: Self.api)!
        components.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "format", value: "json"),
            .init(name: "sites", value: site),
            .init(name: "titles", value: title),
            .init(name: "normalize", value: "1"),
            .init(name: "props", value: "claims|descriptions"),
            .init(name: "languages", value: "tr|en"),
        ]
        guard let url = components.url,
              let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let entities = json["entities"] as? [String: Any] else { return nil }
        return entities.values.compactMap { $0 as? [String: Any] }.first { $0["missing"] == nil && $0["id"] != nil }
    }

    /// Mimar, üslup gibi bağlı kayıtların adları (uygulamanın dilinde, yoksa İngilizce).
    private func labels(_ ids: [String], language: String) async -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(string: Self.api)!
        components.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "format", value: "json"),
            .init(name: "ids", value: ids.prefix(50).joined(separator: "|")),
            .init(name: "props", value: "labels"),
            .init(name: "languages", value: "\(language)|en"),
        ]
        guard let url = components.url,
              let result = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let entities = json["entities"] as? [String: [String: Any]] else { return [:] }
        return entities.compactMapValues { entity in
            let labels = entity["labels"] as? [String: [String: Any]]
            return (labels?[language]?["value"] ?? labels?["en"]?["value"]) as? String
        }
    }

    // MARK: - Ayrıştırma

    /// Kaydın bilgileri ve adı ayrıca sorulacak bağlı kayıtlar (özellik → kimlikler).
    static func parse(_ entity: [String: Any], language: String) -> (Facts, [String: [String]]) {
        let claims = entity["claims"] as? [String: [[String: Any]]] ?? [:]
        func values(_ property: String) -> [Any] {
            let statements = claims[property] ?? []
            // "Tercih edilen" değerler önce, "kullanımdan kalkmış"lar hiç.
            let ranked = statements.filter { $0["rank"] as? String != "deprecated" }
                .sorted { ($0["rank"] as? String == "preferred" ? 0 : 1) < ($1["rank"] as? String == "preferred" ? 0 : 1) }
            return ranked.compactMap { (($0["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] }
        }
        func ids(_ property: String) -> [String] {
            Array(values(property).compactMap { ($0 as? [String: Any])?["id"] as? String }.prefix(3))
        }
        func amount(_ value: Any?) -> Double? {
            ((value as? [String: Any])?["amount"] as? String).flatMap { Double($0.replacingOccurrences(of: "+", with: "")) }
        }

        var facts = Facts(id: entity["id"] as? String ?? "")
        let descriptions = entity["descriptions"] as? [String: [String: Any]]
        facts.description = (descriptions?[language]?["value"] ?? descriptions?["en"]?["value"]) as? String
        if let time = values("P571").first as? [String: Any], let stamp = time["time"] as? String {
            facts.built = builtText(stamp, precision: time["precision"] as? Int ?? 0, language: language)
        }
        // Yükseklik yalnızca metre olarak verildiyse.
        if let height = values("P2048").first as? [String: Any],
           (height["unit"] as? String)?.hasSuffix("/Q11573") == true {
            facts.height = amount(height)
        }
        facts.visitorsPerYear = values("P1174").compactMap { amount($0) }.first.map { Int($0) }
        facts.website = (values("P856").first as? String).flatMap(URL.init(string:))
        if let file = values("P18").first as? String { facts.imageURL = commonsImage(file) }
        return (facts, ["P84": ids("P84"), "P149": ids("P149"), "P1435": ids("P1435")].filter { !$0.value.isEmpty })
    }

    /// Wikidata tarihi ("+1110-00-00T00:00:00Z") okunur yıla; yüzyıl ve
    /// daha kaba tarihler gösterilmez (yanlış yüzyıl söylememek için).
    static func builtText(_ stamp: String, precision: Int, language: String) -> String? {
        let negative = stamp.hasPrefix("-")
        guard let year = Int(stamp.dropFirst().prefix { $0 != "-" }), year > 0 else { return nil }
        let turkish = language == "tr"
        switch precision {
        case 9...:
            return negative ? (turkish ? "MÖ \(year)" : "\(year) BC") : "\(year)"
        case 8 where !negative:
            let decade = year / 10 * 10
            return turkish ? "\(decade)'\(turkishPluralSuffix(decade))" : "\(decade)s"
        default:
            return nil
        }
    }

    /// "1960'lar", "1970'ler": son okunan sözcüğün ünlüsüne göre (altmış,
    /// yetmiş; sıfırla bitenlerde yüz ya da bin).
    static func turkishPluralSuffix(_ decade: Int) -> String {
        let tens = (decade / 10) % 10
        if tens == 0 { return "ler" }  // yüz, bin
        return [2, 5, 7, 8].contains(tens) ? "ler" : "lar"
    }

    /// Commons dosyasının küçük resim adresi.
    static func commonsImage(_ file: String, width: Int = 800) -> URL? {
        let name = file.replacingOccurrences(of: " ", with: "_")
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "&?#+"))) else {
            return nil
        }
        return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=\(width)")
    }
}

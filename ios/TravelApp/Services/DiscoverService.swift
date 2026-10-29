import Foundation

/// Keşfet içeriği, hepsi ücretsiz ve CC BY-SA: fotoğraf ve konum
/// Wikipedia'dan; ülkenin şehir listesi ve şehir rehberi (nasıl bir yer,
/// ne zaman gidilir...) Wikivoyage'dan, Türkçeye çevrilerek. Manuel
/// küratörlük yok. Okunan her şey telefonda saklanır.
actor DiscoverService {
    static let shared = DiscoverService()

    enum Site: String {
        case wikipedia, wikivoyage
    }

    /// Bir sayfanın konumu, fotoğrafı ve uygulama dilindeki başlığı.
    struct PageInfo: Codable, Hashable {
        var latitude: Double?
        var longitude: Double?
        var photo: URL?
        /// Türkçe Wikipedia'daki başlığı ("Munich" → "Münih").
        var localTitle: String?
    }

    /// Ülke sayfasındaki şehir (Wikivoyage "Cities" listesi).
    struct GuideCity: Codable, Hashable, Identifiable {
        /// Wikivoyage başlığı ("Nara (city)").
        var title: String
        /// Görünen ad ("Nara").
        var name: String
        /// Tek satırlık İngilizce açıklama.
        var summary: String
        var latitude: Double?
        var longitude: Double?

        var id: String { title }
    }

    /// Şehir rehberinden bir bölüm; başlık İngilizce ("Get in").
    struct GuideSection: Codable, Hashable, Identifiable {
        var heading: String
        var text: String

        var id: String { heading }
    }

    /// Uygulamanın dili (Ayarlar, varsayılan Türkçe); Türkçeyse şehir adları
    /// Türkçe Wikipedia'dan alınır, açıklamalar Türkçeye çevrilir.
    static var language: String { AppLanguage.current.rawValue }

    private let pages = DiskCache<PageInfo>(name: "discover-pages")
    private let placeLists = DiskCache<[GuideCity]>(name: "wikivoyage-places")
    private let guides = DiskCache<[GuideSection]>(name: "wikivoyage-guides")
    private let translations = DiskCache<String>(name: "discover-translations")
    private let englishTitles = DiskCache<String>(name: "english-titles")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TravelApp/0.1 (https://github.com/amy60946/travel-app)"]
        return URLSession(configuration: config)
    }()

    // MARK: - Sayfa bilgisi (konum, fotoğraf)

    /// Başlıkların konumu ve fotoğrafı, 50'şerli toplu istekle. Wikivoyage'da
    /// fotoğraf sayfanın üstündeki geniş manzara (banner).
    func info(_ titles: [String], from site: Site) async -> [String: PageInfo] {
        var result: [String: PageInfo] = [:]
        var missing: [String] = []
        for title in Set(titles) where !title.isEmpty {
            if let cached = pages[Self.pageKey(title, site)] {
                result[title] = cached
            } else {
                missing.append(title)
            }
        }
        for start in stride(from: 0, to: missing.count, by: 50) {
            let chunk = Array(missing[start..<min(start + 50, missing.count)])
            guard let fetched = await fetchInfo(chunk, from: site) else { continue }
            for title in chunk {
                let info = fetched[title] ?? PageInfo()
                pages[Self.pageKey(title, site)] = info
                result[title] = info
            }
        }
        return result
    }

    /// Wikipedia'daki yerel ad uygulamanın diline bağlı; saklarken dil de anahtarda.
    private static func pageKey(_ title: String, _ site: Site) -> String {
        site == .wikipedia && language != "en" ? "\(site.rawValue)|\(language)|\(title)" : "\(site.rawValue)|\(title)"
    }

    /// Şehrin ya da yerin fotoğrafı: önce Wikipedia, yoksa Wikivoyage manzarası.
    func photo(_ title: String) async -> URL? {
        if let photo = await info([title], from: .wikipedia)[title]?.photo { return photo }
        return await info([title], from: .wikivoyage)[title]?.photo
    }

    /// Uygulama dilindeki şehir adının İngilizce Wikipedia başlığı
    /// ("Kapadokya" → "Cappadocia"). Bulunamazsa nil.
    func englishTitle(for name: String) async -> String? {
        guard Self.language != "en" else { return name }
        if let cached = englishTitles[name] { return cached.isEmpty ? nil : cached }
        var components = URLComponents(string: "https://\(Self.language).wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "langlinks"),
            .init(name: "lllang", value: "en"),
            .init(name: "redirects", value: "1"),
            .init(name: "titles", value: name),
        ]
        struct Response: Decodable {
            struct Query: Decodable {
                struct Page: Decodable {
                    struct Link: Decodable { var title: String }
                    var langlinks: [Link]?
                }
                var pages: [Page]?
            }
            var query: Query?
        }
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }
        let title = decoded.query?.pages?.first?.langlinks?.first?.title
        englishTitles[name] = title ?? ""
        return title
    }

    // MARK: - Ülkenin şehirleri

    /// Ülkenin Wikivoyage sayfasındaki yerler: "Cities" (en önemli 9-10 şehir)
    /// ve "Other destinations" (milli parklar, adalar…).
    func places(countryTitle title: String) async -> [GuideCity] {
        if let cached = placeLists[title] { return cached }
        guard let text = await wikitext(title) else { return [] }
        let list = Self.cityList(fromWikitext: text, includingOther: true)
        if !list.isEmpty { placeLists[title] = list }
        return list
    }

    // MARK: - Şehir rehberi

    /// Şehrin Wikivoyage rehberinden bölümler: nasıl bir yer, iklim, nasıl
    /// gidilir, nasıl dolaşılır, nerede kalınır, güvenlik, saygı.
    func guide(cityTitle title: String) async -> [GuideSection] {
        if let cached = guides[title] { return cached }
        var components = URLComponents(string: "https://en.wikivoyage.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "extracts"),
            .init(name: "explaintext", value: "1"),
            .init(name: "exsectionformat", value: "wiki"),
            .init(name: "redirects", value: "1"),
            .init(name: "titles", value: title),
        ]
        struct Response: Decodable {
            struct Query: Decodable {
                struct Page: Decodable { var extract: String? }
                var pages: [Page]?
            }
            var query: Query?
        }
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let extract = try? JSONDecoder().decode(Response.self, from: data).query?.pages?.first?.extract
        else { return [] }
        let sections = Self.guideSections(fromExtract: extract)
        if !sections.isEmpty { guides[title] = sections }
        return sections
    }

    // MARK: - Çeviri

    /// Türkçesi; bir kez çevrilip saklanır. Çevrilemezse nil.
    func turkish(_ text: String, key: String) async -> String? {
        if let cached = translations[key] { return cached }
        guard let translated = await Translator.shared.toTurkish(text) else { return nil }
        translations[key] = translated
        return translated
    }

    /// Satırları tek seferde çevirir; satır sayısı tutmazsa nil.
    func turkishLines(_ lines: [String], key: String) async -> [String]? {
        guard !lines.isEmpty else { return [] }
        let joined = lines.map { $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n")
        guard let translated = await turkish(joined, key: key) else { return nil }
        let result = translated.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return result.count == lines.count ? result : nil
    }

    // MARK: - İstekler

    private func fetchInfo(_ titles: [String], from site: Site) async -> [String: PageInfo]? {
        let host = site == .wikipedia ? "en.wikipedia.org" : "en.wikivoyage.org"
        var components = URLComponents(string: "https://\(host)/w/api.php")!
        var items: [URLQueryItem] = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "redirects", value: "1"),
            .init(name: "colimit", value: "max"),
            .init(name: "piprop", value: "thumbnail"),
            .init(name: "pithumbsize", value: "800"),
            .init(name: "pilimit", value: "50"),
            .init(name: "titles", value: titles.joined(separator: "|")),
        ]
        if site == .wikipedia && Self.language != "en" {
            items += [.init(name: "prop", value: "coordinates|pageimages|langlinks"),
                      .init(name: "lllang", value: Self.language),
                      .init(name: "lllimit", value: "max")]
        } else if site == .wikipedia {
            items.append(.init(name: "prop", value: "coordinates|pageimages"))
        } else {
            items += [.init(name: "prop", value: "coordinates|pageimages|pageprops"),
                      .init(name: "ppprop", value: "wpb_banner")]
        }
        components.queryItems = items
        struct Response: Decodable {
            struct Query: Decodable {
                struct Rename: Decodable { var from: String; var to: String }
                struct Page: Decodable {
                    struct Coordinate: Decodable { var lat: Double; var lon: Double }
                    struct Thumbnail: Decodable { var source: URL }
                    struct Props: Decodable { var wpb_banner: String? }
                    struct Link: Decodable { var title: String }
                    var title: String
                    var coordinates: [Coordinate]?
                    var thumbnail: Thumbnail?
                    var pageprops: Props?
                    var langlinks: [Link]?
                }
                var normalized: [Rename]?
                var redirects: [Rename]?
                var pages: [Page]?
            }
            var query: Query?
        }
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }
        let query = decoded.query
        let pagesByTitle = Dictionary((query?.pages ?? []).map { ($0.title, $0) }) { first, _ in first }
        let normalized = Dictionary((query?.normalized ?? []).map { ($0.from, $0.to) }) { first, _ in first }
        let redirects = Dictionary((query?.redirects ?? []).map { ($0.from, $0.to) }) { first, _ in first }
        var result: [String: PageInfo] = [:]
        for title in titles {
            let name = normalized[title] ?? title
            guard let page = pagesByTitle[redirects[name] ?? name] else { continue }
            let banner = page.pageprops?.wpb_banner.flatMap(Self.bannerURL)
            result[title] = PageInfo(latitude: page.coordinates?.first?.lat,
                                     longitude: page.coordinates?.first?.lon,
                                     photo: banner ?? page.thumbnail.flatMap { Self.isPhoto($0.source) ? $0.source : nil },
                                     localTitle: page.langlinks?.first?.title)
        }
        return result
    }

    private func wikitext(_ title: String) async -> String? {
        var components = URLComponents(string: "https://en.wikivoyage.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "parse"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "wikitext"),
            .init(name: "redirects", value: "1"),
            .init(name: "page", value: title),
        ]
        struct Response: Decodable {
            struct Parse: Decodable { var wikitext: String }
            var parse: Parse?
        }
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return (try? JSONDecoder().decode(Response.self, from: data))?.parse?.wikitext
    }

    /// Wikivoyage manzara dosyasının (banner) adresi.
    private static func bannerURL(_ file: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.()")
        guard let encoded = file.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://en.wikivoyage.org/wiki/Special:FilePath/\(encoded)?width=1200")
    }

    // MARK: - Ayrıştırma (birim testli)

    /// Bölge haritası, bayrak gibi çizimler manzara fotoğrafı sayılmaz
    /// (ör. Wikivoyage'da manzarası olmayan ülkelerin sayfa resmi haritadır).
    static func isPhoto(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.contains(".svg") { return false }
        let words = Set(name.split { !$0.isLetter }.map(String.init))
        return words.isDisjoint(with: ["map", "maps", "locator", "location", "region", "regions", "flag"])
    }

    /// Vikimetinde bir ana bölümün (== Başlık ==) içi; alt bölümler dahil.
    static func section(_ names: [String], in wikitext: String) -> String? {
        var body: [String] = []
        var found = false
        for line in wikitext.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=="), !trimmed.hasPrefix("===") {
                if found { break }
                let heading = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                found = names.contains { $0.caseInsensitiveCompare(heading) == .orderedSame }
                continue
            }
            if found { body.append(line) }
        }
        return found ? body.joined(separator: "\n") : nil
    }

    /// Ülke sayfasının "Cities" bölümündeki şehirler. Satırlar "* [[Paris]] —
    /// açıklama" ya da "{{marker|type=city|name=[[Paris]]|lat=..}} — açıklama"
    /// biçiminde, bazen Citylist şablonunda "| 1=..." diye.
    /// `includingOther` doğruysa "Other destinations" (milli parklar, adalar…)
    /// da eklenir; ülke sayfasındaki "yerler" listesi ve kartlardaki sayı için.
    static func cityList(fromWikitext text: String, includingOther: Bool = false) -> [GuideCity] {
        var bodies = [section(["Cities", "Cities and towns", "Towns and cities", "Major cities"], in: text)]
        if includingOther { bodies.append(section(["Other destinations"], in: text)) }
        let body = bodies.compactMap { $0 }.joined(separator: "\n")
        guard !body.isEmpty else { return [] }
        var result: [GuideCity] = []
        for raw in body.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("*") {
                line = String(line.drop { $0 == "*" || $0 == " " })
            } else if let item = line.range(of: "^\\|\\s*\\d+\\s*=", options: .regularExpression) {
                line = String(line[item.upperBound...])
            } else {
                continue
            }
            guard let link = firstLink(in: line), !result.contains(where: { $0.title == link.title }) else { continue }
            var summary = plainText(line)
            if summary.hasPrefix(link.label) { summary = String(summary.dropFirst(link.label.count)) }
            summary = String(summary.drop { " —–-:,;".contains($0) })
            result.append(GuideCity(title: link.title, name: link.name, summary: summary,
                                    latitude: number("lat", in: line), longitude: number("long", in: line)))
        }
        return result
    }

    /// Satırdaki ilk iç bağlantı: [[Nara (city)|Nara]] → başlık "Nara (city)",
    /// yazı "Nara", ad "Nara". Dosya ve kategori bağlantıları atlanır.
    static func firstLink(in line: String) -> (title: String, label: String, name: String)? {
        var rest = line[...]
        while let open = rest.range(of: "[[") {
            guard let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) else { return nil }
            let parts = rest[open.upperBound..<close.lowerBound]
                .split(separator: "|", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            rest = rest[close.upperBound...]
            guard var title = parts.first, !title.isEmpty, !title.contains(":") else { continue }
            if let hash = title.firstIndex(of: "#") { title = String(title[..<hash]) }
            let label = parts.count > 1 ? parts[1] : title
            let name = label.replacingOccurrences(of: "\\s*\\([^)]*\\)$", with: "", options: .regularExpression)
            return (title, label, name)
        }
        return nil
    }

    /// Vikimetinden düz yazı: şablonlar, dipnotlar, dosyalar ve biçim işaretleri çıkar.
    static func plainText(_ wikitext: String) -> String {
        var text = wikitext
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<ref[^>]*/>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<ref[^>]*>[\\s\\S]*?</ref>", with: "", options: .regularExpression)
        // Şablonlar ({{...}}) içten dışa silinir.
        while let template = text.range(of: "\\{\\{[^{}]*\\}\\}", options: .regularExpression) {
            text.removeSubrange(template)
        }
        text = text.replacingOccurrences(of: "\\[\\[(File|Image):[^\\]]*\\]\\]", with: "",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "\\[\\[(?:[^|\\]]*\\|)?([^\\]]*)\\]\\]", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[https?://[^ \\]]+ ?([^\\]]*)\\]", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "'{2,}", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Rehberde gösterilen bölümler, sırasıyla (başka adla da yazılabilir).
    static let guideHeadings: [[String]] = [
        ["Understand"], ["Climate", "When to go", "Weather"], ["Get in"], ["Get around"],
        ["Sleep"], ["Stay safe"], ["Respect"],
    ]

    /// Düz yazı rehberden (== Understand == başlıklı) bölümler. Bölümün
    /// kendi yazısı yoksa ilk alt bölümün yazısı alınır ("Get in" → "By plane").
    static func guideSections(fromExtract text: String) -> [GuideSection] {
        var entries: [(level: Int, heading: String, lines: [String])] = [(0, "", [])]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=="), trimmed.hasSuffix("==") {
                let level = trimmed.prefix { $0 == "=" }.count
                entries.append((level, trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= ")), []))
            } else {
                entries[entries.count - 1].lines.append(trimmed)
            }
        }
        var result: [GuideSection] = []
        for names in guideHeadings {
            guard let index = entries.firstIndex(where: { entry in
                names.contains { $0.caseInsensitiveCompare(entry.heading) == .orderedSame }
            }) else { continue }
            var body = excerpt(entries[index].lines.joined(separator: "\n"))
            if body.isEmpty, index + 1 < entries.count, entries[index + 1].level > entries[index].level {
                body = excerpt(entries[index + 1].lines.joined(separator: "\n"))
            }
            if !body.isEmpty { result.append(GuideSection(heading: names[0], text: body)) }
        }
        return result
    }

    /// İlk paragraflar, yaklaşık `limit` harfe kadar; tek paragraf çok
    /// uzunsa cümle sonundan kesilir.
    static func excerpt(_ text: String, limit: Int = 700) -> String {
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = ""
        for paragraph in paragraphs {
            if result.isEmpty {
                result = paragraph
            } else if result.count + paragraph.count <= limit {
                result += "\n\n" + paragraph
            } else {
                break
            }
        }
        if result.count > limit + 300 {
            let head = String(result.prefix(limit + 300))
            if let end = head.range(of: ". ", options: .backwards) {
                result = String(head[..<end.lowerBound]) + "."
            } else {
                result = head + "…"
            }
        }
        return result
    }

    private static func number(_ key: String, in line: String) -> Double? {
        guard let range = line.range(of: "\\|\\s*\(key)\\s*=\\s*-?[0-9.]+", options: .regularExpression),
              let value = line[range].split(separator: "=").last
        else { return nil }
        return Double(value.trimmingCharacters(in: .whitespaces))
    }
}

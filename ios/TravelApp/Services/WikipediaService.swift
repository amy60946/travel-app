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

    /// Sayfanın tamamı, başlıklarıyla (Giriş özetin içinde; kaynakça ve dış
    /// bağlantılar yok). Okunur ve dinlenir.
    struct Article: Codable, Equatable {
        struct Section: Codable, Equatable, Identifiable {
            var heading: String
            var text: String
            var id: String { heading }
        }
        var sections: [Section]
        var language: String
        var translatedFrom: String? = nil

        /// Dinlemek için: başlıklar ve yazılar art arda.
        var spokenText: String {
            sections.map { "\($0.heading).\n\($0.text)" }.joined(separator: "\n\n")
        }
    }

    struct PopularPlace: Identifiable, Equatable {
        /// İngilizce Wikipedia başlığı.
        var title: String
        var latitude: Double
        var longitude: Double
        var monthlyViews: Int
        var thumbnailURL: URL?
        /// Uygulama dilindeki sayfanın adı (ör. Türkçe), yoksa nil.
        var localTitle: String?
        var id: String { title }
        /// Listede görünen ad.
        var name: String { localTitle ?? title }
    }

    /// Anlatım dili: uygulamanın dili (Ayarlar, varsayılan Türkçe); telefonun
    /// dili ne olursa olsun.
    static var narrationLanguage: String { AppLanguage.current.rawValue }

    /// Bir kez okunan özet ve fotoğraf listesi telefonda saklanır; internetsiz de açılır.
    private let summaries = DiskCache<Summary>(name: "wikipedia-summaries")
    private let photoLists = DiskCache<[URL]>(name: "wikipedia-photos")
    private let placePhotos = DiskCache<URL>(name: "place-photos")
    private let articles = DiskCache<Article>(name: "wikipedia-articles")
    /// Bu açılışta fotoğrafı bulunamayan yerler (yeniden sorulmaz).
    private var missingPhotos: Set<String> = []
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

    /// Sayfanın tamamı, başlık başlık. İstenen dilde sayfa yoksa İngilizcesi
    /// bölüm bölüm Türkçeye çevrilir (Türkçe istenmişse).
    func article(englishTitle: String, language: String = WikipediaService.narrationLanguage) async -> Article? {
        let key = "\(language)|\(englishTitle)"
        if let cached = articles[key] { return cached }
        if language != "en", let local = try? await localTitle(for: englishTitle, language: language),
           let sections = await fetchSections(title: local, language: language), !sections.isEmpty {
            let result = Article(sections: sections, language: language)
            articles[key] = result
            return result
        }
        guard let english = await fetchSections(title: englishTitle, language: "en"), !english.isEmpty else { return nil }
        guard language == "tr" else {
            let result = Article(sections: english, language: "en")
            articles[key] = result
            return result
        }
        let headings = await Translator.shared.toTurkish(english.map(\.heading).joined(separator: "\n"))?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var translated: [Article.Section] = []
        for (index, section) in english.enumerated() {
            guard let text = await Translator.shared.toTurkish(section.text) else { break }
            let heading = headings?.count == english.count ? headings?[index] ?? section.heading : section.heading
            translated.append(Article.Section(heading: heading, text: text))
        }
        guard !translated.isEmpty else { return nil }
        let result = Article(sections: translated, language: "tr", translatedFrom: "en")
        if translated.count == english.count { articles[key] = result }
        return result
    }

    private func fetchSections(title: String, language: String) async -> [Article.Section]? {
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
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
        else { return nil }
        return Self.articleSections(fromExtract: extract)
    }

    /// Düz yazı sayfadan (== Başlık ==) ana bölümler; alt başlıklar yazının
    /// içinde kalır. Kaynakça, dış bağlantılar gibi bölümler alınmaz; toplam
    /// yaklaşık `limit` harfe kadar.
    static func articleSections(fromExtract text: String, limit: Int = 8000) -> [Article.Section] {
        let skipped: Set<String> = [
            "references", "see also", "external links", "notes", "further reading", "bibliography",
            "sources", "citations", "gallery", "footnotes", "explanatory notes",
            "kaynakça", "kaynaklar", "dış bağlantılar", "ayrıca bakınız", "notlar", "dipnotlar",
            "galeri", "konuyla ilgili yayınlar", "ek okumalar",
        ]
        var sections: [(heading: String, lines: [String], hasText: Bool)] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=="), trimmed.hasSuffix("==") {
                let level = trimmed.prefix { $0 == "=" }.count
                let heading = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                if level == 2 {
                    sections.append((heading, [], false))
                } else if !sections.isEmpty {
                    sections[sections.count - 1].lines.append(heading + ".")
                }
            } else if !sections.isEmpty, !trimmed.isEmpty {
                sections[sections.count - 1].lines.append(trimmed)
                sections[sections.count - 1].hasText = true
            }
        }
        var result: [Article.Section] = []
        var total = 0
        for section in sections where section.hasText && !skipped.contains(section.heading.lowercased()) {
            let body = DiscoverService.excerpt(section.lines.joined(separator: "\n"), limit: min(limit, 3500))
            if total > 0 && total + body.count > limit { break }
            result.append(Article.Section(heading: section.heading, text: body))
            total += body.count
        }
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

    /// Bir noktanın 10 km çevresindeki Wikipedia sayfaları (en çok 300),
    /// son 30 günde en çok okunandan aza. Ad uygulamanın dilinde (Türkçe
    /// sayfası varsa Türkçe adı).
    func popularPlaces(latitude: Double, longitude: Double, limit: Int = 40) async throws -> [PopularPlace] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "list", value: "geosearch"),
            .init(name: "gscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "gsradius", value: "10000"),
            .init(name: "gslimit", value: "300"),
            .init(name: "gsprop", value: "type"),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var geosearch: [Page] }
            struct Page: Decodable { var title: String; var lat: Double; var lon: Double; var type: String? }
            var query: Query?
        }
        let (data, _) = try await session.data(from: components.url!)
        let nearby = (try JSONDecoder().decode(Response.self, from: data).query?.geosearch ?? [])
            .filter { Self.isSight($0.title) && Self.isSight(type: $0.type) }
        // Okunma sayısı, fotoğraf ve yerel ad 50'şerli toplu istekle, aynı anda.
        let language = Self.narrationLanguage
        let details = await withTaskGroup(of: [String: PageDetails].self, returning: [String: PageDetails].self) { group in
            for start in stride(from: 0, to: nearby.count, by: 50) {
                let titles = nearby[start..<min(start + 50, nearby.count)].map(\.title)
                group.addTask { await self.pageDetails(titles, language: language) }
            }
            var all: [String: PageDetails] = [:]
            for await chunk in group { all.merge(chunk) { first, _ in first } }
            return all
        }
        let places = nearby.filter { Self.isSight(description: details[$0.title]?.description) }.map { page in
            let detail = details[page.title]
            return PopularPlace(title: page.title, latitude: page.lat, longitude: page.lon,
                                monthlyViews: detail?.views ?? 0, thumbnailURL: detail?.thumbnail,
                                localTitle: detail?.localTitle)
        }
        let sorted = places.sorted { $0.monthlyViews > $1.monthlyViews }
        return Array(sorted.prefix(limit))
    }

    private struct PageDetails {
        var views = 0
        var thumbnail: URL?
        var localTitle: String?
        var description: String?
    }

    private func pageDetails(_ titles: [String], language: String) async -> [String: PageDetails] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        var items: [URLQueryItem] = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "pvipdays", value: "30"),
            .init(name: "piprop", value: "thumbnail"),
            .init(name: "pithumbsize", value: "300"),
            .init(name: "pilimit", value: "50"),
            .init(name: "titles", value: titles.joined(separator: "|")),
        ]
        if language == "en" {
            items.append(.init(name: "prop", value: "pageviews|pageimages|description"))
        } else {
            items += [.init(name: "prop", value: "pageviews|pageimages|description|langlinks"),
                      .init(name: "lllang", value: language),
                      .init(name: "lllimit", value: "max")]
        }
        components.queryItems = items
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page] }
            struct Page: Decodable {
                struct Thumbnail: Decodable { var source: URL }
                struct Link: Decodable { var title: String }
                var title: String
                var pageviews: [String: Int?]?
                var thumbnail: Thumbnail?
                var langlinks: [Link]?
                var description: String?
            }
            var query: Query?
        }
        guard let url = components.url, let (data, _) = try? await session.data(from: url),
              let pages = try? JSONDecoder().decode(Response.self, from: data).query?.pages
        else { return [:] }
        var result: [String: PageDetails] = [:]
        for page in pages {
            let views = page.pageviews?.values.compactMap { $0 }.reduce(0, +) ?? 0
            let local = page.langlinks?.first?.title
                .replacingOccurrences(of: "\\s*\\([^)]*\\)$", with: "", options: .regularExpression)
            result[page.title] = PageDetails(views: views, thumbnail: page.thumbnail?.source, localTitle: local,
                                             description: page.description)
        }
        return result
    }

    /// Bir yerin gerçek fotoğrafı (listelerde tür simgesi yerine): Wikipedia
    /// sayfası (biliniyorsa ya da 300 m içinde adı tutan sayfa), yoksa 150 m
    /// içinde çekilmiş bir Wikimedia Commons fotoğrafı. Bulunan saklanır.
    func photo(name: String, city: String, latitude: Double, longitude: Double,
               englishTitle: String? = nil) async -> URL? {
        let key = "\(englishTitle ?? name)|\((latitude * 1000).rounded() / 1000)|\((longitude * 1000).rounded() / 1000)"
        if let cached = placePhotos[key] { return cached }
        guard !missingPhotos.contains(key) else { return nil }
        // Haritada çok pin varken Wikipedia'ya aynı anda en çok 4 istek.
        await acquireLookup()
        defer { releaseLookup() }
        if let cached = placePhotos[key] { return cached }
        guard !Task.isCancelled else { return nil }
        var title = englishTitle
        if title == nil, !name.isEmpty {
            title = await findArticle(name: name, city: city, latitude: latitude, longitude: longitude)
        }
        var url: URL?
        if let title { url = await thumbnailURL(englishTitle: title) }
        if url == nil { url = await nearbyPhotos(latitude: latitude, longitude: longitude).first }
        if let url {
            placePhotos[key] = url
        } else if !Task.isCancelled {
            missingPhotos.insert(key)
        }
        return url
    }

    private var runningLookups = 0
    private var waitingLookups: [CheckedContinuation<Void, Never>] = []

    private func acquireLookup() async {
        if runningLookups < 4 {
            runningLookups += 1
            return
        }
        await withCheckedContinuation { waitingLookups.append($0) }
    }

    private func releaseLookup() {
        if waitingLookups.isEmpty {
            runningLookups -= 1
        } else {
            waitingLookups.removeFirst().resume()
        }
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
                        "expressway", "highway", "route", "list of", "chongryon", "constituency",
                        "empire of", "kingdom of", "republic of", "shogunate", "dynasty"]
        return !excluded.contains { lower.contains($0) }
    }

    /// Wikipedia koordinatının türü: ülke, il, şehir, istasyon, havalimanı,
    /// okul ve olay sayfaları gezilecek yer değildir ("city(8000000)" gibi
    /// nüfuslu yazımlar da).
    static func isSight(type: String?) -> Bool {
        guard let type = type?.lowercased().split(separator: "(").first.map(String.init) else { return true }
        let excluded = ["country", "state", "adm1st", "adm2nd", "adm3rd", "city", "railwaystation",
                        "airport", "edu", "event", "satellite"]
        return !excluded.contains(type)
    }

    /// Kısa açıklaması ülke, eski devlet, şehir, istasyon, okul, şirket ya da
    /// kurum diyen sayfalar ("Japon İmparatorluğu" gibi) listeye alınmaz.
    static func isSight(description: String?) -> Bool {
        guard let lower = description?.lowercased() else { return true }
        let excluded = ["country in", "island country", "sovereign state", "historical state", "former country",
                        "historical country", "state from", "empire from", "special ward", "prefecture of",
                        "capital of", "capital city", "city in", "city of", "town in", "municipality",
                        "railway station", "metro station", "subway station", "train station", "railway line",
                        "university", "school in", "college in", "company", "corporation", "hospital", "embassy",
                        "ministry", "political party", "electoral", "constituency", "airport",
                        "expressway", "stock exchange", "newspaper", "broadcaster", "television station"]
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

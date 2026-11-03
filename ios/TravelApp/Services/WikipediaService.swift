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
    /// "-2": eşleşmesi gevşek eski fotoğraflar (yakındaki rastgele bir
    /// fotoğraf) bir kez yeniden aranır (2026-10-30).
    private let placePhotos = DiskCache<URL>(name: "place-photos-2")
    private let articles = DiskCache<Article>(name: "wikipedia-articles")
    /// Bu açılışta bulunan popüler yerler (şehir planı ve "Yer ekle" aynı listeyi kullanır).
    private var popularCache: [String: [PopularPlace]] = [:]
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
        if let local = Self.localOnly(englishTitle) {
            // İngilizce sayfası olmayan yer: yalnızca o dilde okunur.
            guard local.language == language else { return nil }
            return await localSummary(englishTitle)
        }
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
        if let local = Self.localOnly(englishTitle) {
            guard local.language == language,
                  let sections = await fetchSections(title: local.title, language: local.language), !sections.isEmpty
            else { return nil }
            let result = Article(sections: sections, language: language)
            articles[key] = result
            return result
        }
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
        if Self.localOnly(englishTitle) != nil { return await localSummary(englishTitle)?.thumbnailURL }
        return await englishSummary(englishTitle)?.thumbnailURL
    }

    /// İngilizce sayfası olmayan yerin ("tr:Başlık") kendi dilindeki özeti.
    private func localSummary(_ encoded: String) async -> Summary? {
        guard let local = Self.localOnly(encoded) else { return nil }
        let key = "\(local.language)|\(encoded)"
        if let cached = summaries[key] { return cached }
        guard let result = try? await fetchSummary(title: local.title, language: local.language) else { return nil }
        summaries[key] = result
        return result
    }

    /// İngilizce sayfası olmayan yerler (ör. yalnızca Türkçe sayfası olan
    /// bir cami) "tr:Başlık" diye saklanır. İngilizce başlıklar büyük
    /// harfle başladığı için karışmaz.
    static func localOnly(_ title: String) -> (language: String, title: String)? {
        guard let colon = title.firstIndex(of: ":") else { return nil }
        let prefix = title[..<colon]
        guard (2...3).contains(prefix.count),
              prefix.allSatisfy({ $0.isASCII && $0.isLetter && $0.isLowercase }) else { return nil }
        let rest = String(title[title.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (String(prefix), rest)
    }

    static func localOnlyTitle(_ title: String, language: String) -> String { "\(language):\(title)" }

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
    /// `radius` metre (en çok 10 km); "Yer ekle"deki "Yakınındaki popüler
    /// yerler" günün her yeri için 1,5 km çevreye bakar.
    func popularPlaces(latitude: Double, longitude: Double, limit: Int = 40,
                       radius: Int = 10_000) async throws -> [PopularPlace] {
        let cacheKey = String(format: "%.3f,%.3f|%@|%d|%d", latitude, longitude, Self.narrationLanguage, limit, radius)
        if let cached = popularCache[cacheKey] { return cached }
        let found = try await fetchPopularPlaces(latitude: latitude, longitude: longitude, limit: limit, radius: radius)
        if !found.isEmpty { popularCache[cacheKey] = found }
        return found
    }

    private func fetchPopularPlaces(latitude: Double, longitude: Double, limit: Int,
                                    radius: Int) async throws -> [PopularPlace] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "list", value: "geosearch"),
            .init(name: "gscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "gsradius", value: "\(min(max(radius, 10), 10_000))"),
            .init(name: "gslimit", value: radius >= 5000 ? "300" : "150"),
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

    /// Okuma izlerinden gelen yerler: okunma, fotoğraf ve uygulama dilindeki
    /// ad; gezilecek yer olmayanlar (semt, istasyon...) çıkar. Sıra korunur.
    func places(_ items: [ReadingTrails.Related]) async -> [PopularPlace] {
        let sights = items.filter { Self.isSight($0.title) }
        guard !sights.isEmpty else { return [] }
        let language = Self.narrationLanguage
        var details: [String: PageDetails] = [:]
        for start in stride(from: 0, to: sights.count, by: 50) {
            let titles = sights[start..<min(start + 50, sights.count)].map(\.title)
            let found = await pageDetails(titles, language: language)
            details.merge(found) { first, _ in first }
        }
        return sights.filter { Self.isSight(description: details[$0.title]?.description) }.map { item in
            let detail = details[item.title]
            return PopularPlace(title: item.title, latitude: item.latitude, longitude: item.longitude,
                                monthlyViews: detail?.views ?? 0, thumbnailURL: detail?.thumbnail,
                                localTitle: detail?.localTitle)
        }
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
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page]? }
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
            var next: [String: String]?
            enum CodingKeys: String, CodingKey { case query, next = "continue" }
        }
        // Okunma sayısı her istekte yalnızca birkaç sayfa için gelir; kalanlar
        // "continue" ile parça parça istenir (yoksa çoğu yer 0 okunmuş görünür
        // ve sıralama bozulur; Kız Kulesi çevresinde denendi, 2026-11-03).
        var result: [String: PageDetails] = [:]
        var continuation: [URLQueryItem] = []
        for _ in 0..<8 {
            components.queryItems = items + continuation
            guard let url = components.url, let (data, _) = try? await session.data(from: url),
                  let decoded = try? JSONDecoder().decode(Response.self, from: data) else { break }
            for page in decoded.query?.pages ?? [] {
                var detail = result[page.title] ?? PageDetails()
                let views = page.pageviews?.values.compactMap { $0 }.reduce(0, +) ?? 0
                detail.views = max(detail.views, views)
                if let thumbnail = page.thumbnail?.source { detail.thumbnail = thumbnail }
                if let local = page.langlinks?.first?.title {
                    detail.localTitle = local.replacingOccurrences(of: "\\s*\\([^)]*\\)$", with: "",
                                                                   options: .regularExpression)
                }
                if let description = page.description { detail.description = description }
                result[page.title] = detail
            }
            guard let next = decoded.next, !next.isEmpty else { break }
            continuation = next.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return result
    }

    /// Bir yerin gerçek fotoğrafı (listelerde tür simgesi yerine): Wikipedia
    /// sayfasının ana fotoğrafı (sayfa biliniyorsa ya da 300 m içinde adı
    /// tutan sayfa), yoksa 150 m içinde çekilmiş ve dosya adında yerin adı
    /// geçen bir Wikimedia Commons fotoğrafı. Emin olunamazsa fotoğraf yok
    /// (türün simgesi görünür): yanlış fotoğraf göstermektense hiç
    /// göstermemek. Bulunan saklanır.
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
        // Sayfada fotoğraf yoksa Wikidata'daki fotoğraf.
        if url == nil, let title { url = await WikidataService.shared.facts(wikipediaTitle: title)?.imageURL }
        if url == nil {
            url = await nearbyPhotos(latitude: latitude, longitude: longitude,
                                     matching: [name, title.map { Self.localOnly($0)?.title ?? $0 }].compactMap { $0 },
                                     city: city).first
        }
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
        let local = Self.localOnly(englishTitle)
        guard let url = Self.restURL(language: local?.language ?? "en", endpoint: "media-list",
                                     title: local?.title ?? englishTitle),
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
    /// çekilmiş fotoğraflar (Wikimedia Commons, 150 m içinde). `names`
    /// verilirse yalnızca dosya adında yerin adından bir kelime geçenler
    /// (ör. "Shibuya Kavşağı" için "File:Shibuya Crossing at night.jpg").
    func nearbyPhotos(latitude: Double, longitude: Double, matching names: [String] = [],
                      city: String = "") async -> [URL] {
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
                var title: String?
                var imageinfo: [Info]?
            }
            var query: Query?
        }
        guard let (data, _) = try? await session.data(from: components.url!),
              let pages = try? JSONDecoder().decode(Response.self, from: data).query?.pages
        else { return [] }
        return pages
            .filter { page in names.isEmpty || names.contains { Self.fileMatches(page.title ?? "", name: $0, city: city) } }
            .compactMap(\.imageinfo?.first)
            .filter { $0.mime == "image/jpeg" || $0.mime == "image/png" }
            .compactMap(\.thumburl)
    }

    /// Wikimedia fotoğrafının sahibi ve lisansı ("Ali Veli · CC BY-SA 4.0");
    /// fotoğraf tam ekrandayken ⓘ düğmesinde gösterilir (lisans gereği).
    struct PhotoCredit: Equatable {
        var author: String
        var license: String
        var page: URL?
    }

    func credit(for url: URL) async -> PhotoCredit? {
        guard let file = Self.commonsFileName(url) else { return nil }
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "titles", value: "File:\(file)"),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "extmetadata|url"),
            .init(name: "iiextmetadatafilter", value: "Artist|LicenseShortName"),
        ]
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page] }
            struct Page: Decodable {
                struct Info: Decodable {
                    struct Field: Decodable { var value: String? }
                    var extmetadata: [String: Field]?
                    var descriptionurl: URL?
                }
                var imageinfo: [Info]?
            }
            var query: Query?
        }
        guard let (data, _) = try? await session.data(from: components.url!),
              let info = try? JSONDecoder().decode(Response.self, from: data).query?.pages.first?.imageinfo?.first
        else { return nil }
        let author = Self.plainText(info.extmetadata?["Artist"]?.value ?? "")
        let license = info.extmetadata?["LicenseShortName"]?.value ?? ""
        guard !author.isEmpty || !license.isEmpty else { return nil }
        return PhotoCredit(author: author, license: license, page: info.descriptionurl)
    }

    /// upload.wikimedia.org adresinden dosya adı (küçük resimde sondan bir önceki parça).
    static func commonsFileName(_ url: URL) -> String? {
        guard url.host()?.hasSuffix("wikimedia.org") == true else { return nil }
        let parts = url.pathComponents
        guard let last = parts.last else { return nil }
        if parts.contains("thumb"), parts.count >= 2 { return parts[parts.count - 2].removingPercentEncoding }
        return last.removingPercentEncoding
    }

    /// HTML etiketlerini atar ("<a href=...>Ali</a>" → "Ali").
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commons dosya adı yeri anlatıyor mu: yerin adındaki genel olmayan
    /// (tür ya da şehir adı olmayan, en az 4 harfli) bir kelime dosya
    /// adında geçiyor.
    static func fileMatches(_ fileTitle: String, name: String, city: String) -> Bool {
        let file = words(fold(fileTitle))
        let significant = significantWords(name, city: city)
        if !significant.isEmpty { return !significant.isDisjoint(with: file) }
        // "Kız Kulesi" gibi yalnızca kısa ve tür kelimelerinden oluşan ad:
        // bütün kelimeleri dosya adında geçmeli.
        let cityWord = fold(city)
        let nameWords = words(fold(name)).filter { $0.count >= 2 && $0 != cityWord }
        return nameWords.count >= 2 && nameWords.isSubset(of: file)
    }

    private static func significantWords(_ text: String, city: String) -> Set<String> {
        let cityWord = fold(city)
        return words(fold(text)).filter {
            $0.count >= 4 && $0 != cityWord && kinds[$0] == nil && !["the", "national", "art", "file"].contains($0)
        }
    }

    /// Kayıtlı yerin Wikipedia sayfası (İngilizce başlığı): 500 m içindeki
    /// sayfalardan adı yerin adıyla örtüşen, en yakını. Ad uygulamanın
    /// dilinde olabilir: İngilizce sayfanın Türkçe adıyla da karşılaştırılır
    /// ("Kız Kulesi" → "Maiden's Tower"). İngilizce sayfası olmayan yer
    /// Türkçe Wikipedia'da aranır ("tr:Başlık"). Emin olunamazsa nil
    /// (yanlış yazı göstermektense hiç göstermemek).
    func findArticle(name: String, city: String, latitude: Double, longitude: Double) async -> String? {
        if case .found(let title) = await lookupArticle(name: name, city: city, latitude: latitude, longitude: longitude) {
            return title
        }
        return nil
    }

    enum ArticleLookup: Equatable {
        case found(String)
        /// Yakında adı tutan sayfa yok.
        case none
        /// İstek yapılamadı (internet yok): sonra yeniden denenir.
        case failed
    }

    func lookupArticle(name: String, city: String, latitude: Double, longitude: Double) async -> ArticleLookup {
        let language = Self.narrationLanguage
        guard let english = await nearbyPages(wiki: "en", linkLanguage: language == "en" ? nil : language,
                                              latitude: latitude, longitude: longitude) else { return .failed }
        if let match = Self.bestMatch(english, name: name, city: city) { return .found(match.title) }
        guard language != "en" else { return .none }
        guard let local = await nearbyPages(wiki: language, linkLanguage: "en",
                                            latitude: latitude, longitude: longitude) else { return .failed }
        guard let match = Self.bestMatch(local, name: name, city: city) else { return .none }
        return .found(match.link ?? Self.localOnlyTitle(match.title, language: language))
    }

    /// Yakındaki bir Wikipedia sayfası: başlığı, başka dildeki adı (varsa) ve uzaklığı.
    struct NearbyPage: Equatable {
        var title: String
        var link: String?
        var distance: Double
    }

    /// Adı en iyi tutan sayfa: önce adı aynı ya da içeren (başlık ya da
    /// öteki dildeki adı), yoksa ortak kelimesi olan; eşitse en yakını.
    static func bestMatch(_ pages: [NearbyPage], name: String, city: String) -> NearbyPage? {
        let sorted = pages.sorted { $0.distance < $1.distance }
        let names = { (page: NearbyPage) in [page.title, page.link].compactMap { $0 }.map(Self.withoutQualifier) }
        return sorted.first { page in names(page).contains { matchesStrongly(title: $0, name: name) } }
            ?? sorted.first { page in names(page).contains { matches(title: $0, name: name, city: city) } }
    }

    /// "Kız Kulesi (İstanbul)" → "Kız Kulesi".
    private static func withoutQualifier(_ title: String) -> String {
        title.replacingOccurrences(of: "\\s*\\([^)]*\\)$", with: "", options: .regularExpression)
    }

    private func nearbyPages(wiki: String, linkLanguage: String?, latitude: Double,
                             longitude: Double) async -> [NearbyPage]? {
        var components = URLComponents(string: "https://\(wiki).wikipedia.org/w/api.php")!
        var items: [URLQueryItem] = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "geosearch"),
            .init(name: "ggscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "ggsradius", value: "500"),
            .init(name: "ggslimit", value: "30"),
            .init(name: "prop", value: linkLanguage == nil ? "coordinates" : "coordinates|langlinks"),
            .init(name: "colimit", value: "max"),
            .init(name: "codistancefrompoint", value: "\(latitude)|\(longitude)"),
        ]
        if let linkLanguage {
            items += [.init(name: "lllang", value: linkLanguage), .init(name: "lllimit", value: "max")]
        }
        components.queryItems = items
        struct Response: Decodable {
            struct Query: Decodable { var pages: [Page]? }
            struct Page: Decodable {
                struct Coordinate: Decodable { var dist: Double? }
                struct Link: Decodable { var title: String }
                var title: String
                var coordinates: [Coordinate]?
                var langlinks: [Link]?
            }
            var query: Query?
        }
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return (decoded.query?.pages ?? []).map { page in
            NearbyPage(title: page.title, link: page.langlinks?.first?.title,
                       distance: page.coordinates?.first?.dist ?? 10_000)
        }
    }

    /// Sayfa başlığı yerin adıyla örtüşüyor mu: biri ötekini içeriyor ya da
    /// genel olmayan (tapınak, park, şehir adı dışında) bir kelime ortak ve
    /// türleri çelişmiyor ("Ueno Station" ile "Ueno Parkı" eşleşmez).
    static func matches(title: String, name: String, city: String) -> Bool {
        if matchesStrongly(title: title, name: name) { return true }
        let a = words(fold(title)), b = words(fold(name))
        let kindsA = Set(a.compactMap { kinds[$0] }), kindsB = Set(b.compactMap { kinds[$0] })
        if !kindsA.isEmpty && !kindsB.isEmpty && kindsA.isDisjoint(with: kindsB) { return false }
        return !significantWords(title, city: city).isDisjoint(with: significantWords(name, city: city))
    }

    static func matchesStrongly(title: String, name: String) -> Bool {
        let a = fold(title), b = fold(name)
        return a == b || (b.count >= 4 && a.contains(b)) || (a.count >= 4 && b.contains(a))
    }

    /// Yer türü bildiren kelimeler (İngilizce, Türkçe, Japonca okunuşu) ve
    /// türleri: "Shibuya Kavşağı" ile "Shibuya Station" eşleşmez.
    private static let kinds: [String: String] = [
        "temple": "temple", "shrine": "temple", "tapinagi": "temple", "tapinak": "temple", "mosque": "temple",
        "camii": "temple", "cami": "temple", "church": "temple", "kilisesi": "temple", "kilise": "temple",
        "jinja": "temple", "jingu": "temple", "cathedral": "temple", "katedrali": "temple",
        "park": "park", "parki": "park", "garden": "park", "gardens": "park", "bahcesi": "park",
        "gyoen": "park", "koen": "park",
        "tower": "tower", "kulesi": "tower", "kule": "tower", "museum": "museum", "muzesi": "museum", "muze": "museum",
        "palace": "palace", "sarayi": "palace", "saray": "palace",
        "station": "station", "istasyonu": "station", "istasyon": "station",
        "market": "market", "bazaar": "market", "carsisi": "market", "carsi": "market", "pazari": "market",
        "mall": "market", "bridge": "bridge", "koprusu": "bridge", "kopru": "bridge",
        "castle": "castle", "kalesi": "castle", "kale": "castle", "hotel": "hotel", "otel": "hotel", "oteli": "hotel",
        "cafe": "cafe", "coffee": "cafe", "kafe": "cafe", "kahve": "cafe", "kahvesi": "cafe",
        "restaurant": "restaurant", "restoran": "restaurant", "lokanta": "restaurant", "lokantasi": "restaurant",
        "street": "street", "sokagi": "street", "sokak": "street", "caddesi": "street", "cadde": "street",
        "avenue": "street", "alley": "street", "yokocho": "street", "dori": "street",
        "crossing": "crossing", "kavsagi": "crossing", "kavsak": "crossing", "intersection": "crossing",
        "square": "square", "meydani": "square", "meydan": "square", "plaza": "square",
        "beach": "beach", "plaji": "beach", "plaj": "beach",
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
                        "empire of", "kingdom of", "republic of", "shogunate", "dynasty",
                        // Olaylar (okuma izlerinde görüldü, 2026-11-03): "Fall of Constantinople".
                        "fall of", "sack of", "siege of", "battle of", "conquest of", "massacre",
                        "earthquake", "bombing of"]
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
                        "expressway", "stock exchange", "newspaper", "broadcaster", "television station",
                        // Kız Kulesi çevresinde görüldü (2026-11-03): semt, ilçe, cezaevi, iskele, metro durağı.
                        "neighbourhood", "neighborhood", "quarter in", "quarter of", "district in", "district of",
                        "district and municipality", "prison", "ferry terminal", "ferry port", "station of the",
                        "train stop", "bus station", "bus terminal", "primary school", "high school",
                        "football club", "sports club", "village in", "suburb of"]
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

import Foundation

/// Kaydedilen Instagram/TikTok gönderilerini yere çevirir:
/// 1. TikTok açıklaması TikTok'un resmi, ücretsiz oEmbed servisinden okunur.
///    Instagram'da kazıma yapılmaz; hesap ve koleksiyon adı kullanılır.
/// 2. Yapay zekâ (Gemini + Groq) gönderilerdeki yerleri toplu bulur.
/// 3. Yerler Apple Haritalar'da aranır. Bulunamayan gönderiler
///    "Yeri belirle" listesine girer.
@MainActor
final class SocialImporter: ObservableObject {
    struct Result {
        var places: [Place] = []
        var pending: [SocialExport.Post] = []
        /// Kısa rapor: kaç gönderide hesap adı vardı, her servis kaç yer buldu.
        var summary: String?
    }

    @Published private(set) var status: String?
    @Published private(set) var progress: (done: Int, total: Int)?

    private let batchSize = 15

    func resolve(_ posts: [SocialExport.Post], knownCities: [AppStore.CitySummary],
                 importer: PlaceImporter) async -> Result {
        defer {
            status = nil
            progress = nil
        }
        guard PlaceAI.isAvailable else { return Result(pending: posts) }

        status = String(localized: "Gönderiler okunuyor…")
        var entries: [String] = []
        for (index, post) in posts.enumerated() {
            progress = (index, posts.count)
            entries.append(await describe(post))
        }

        status = String(localized: "Yapay zekâ yerleri arıyor…")
        var found = Array(repeating: [PlaceAI.Found](), count: posts.count)
        var reports: [PlaceAI.Report] = []
        for start in stride(from: 0, to: posts.count, by: batchSize) {
            progress = (start, posts.count)
            let end = min(start + batchSize, posts.count)
            let batch = await PlaceAI.places(inPosts: Array(entries[start..<end]))
            for (offset, list) in batch.places.enumerated() {
                found[start + offset] = list
            }
            for report in batch.reports {
                if let index = reports.firstIndex(where: { $0.provider == report.provider }) {
                    reports[index].add(report)
                } else {
                    reports.append(report)
                }
            }
        }

        status = String(localized: "Yerler haritada bulunuyor…")
        progress = nil
        var items: [TakeoutParser.Item] = []
        for (index, list) in found.enumerated() {
            let post = posts[index]
            for place in list {
                items.append(TakeoutParser.Item(
                    name: place.name, latitude: nil, longitude: nil,
                    address: place.city ?? post.collection,
                    note: post.author.map { "@\($0)" } ?? "",
                    url: post.url, source: post.source))
            }
        }
        let resolved = await importer.resolve(items, knownCities: knownCities)
        let foundURLs = Set(resolved.added.compactMap(\.sourceURL))
        let withAccount = posts.filter { $0.author != nil }.count
        let summary = [String(localized: "\(posts.count) gönderi · \(withAccount) tanesinde hesap adı var")]
            + reports.map(\.summary)
        return Result(places: resolved.added, pending: posts.filter { !foundURLs.contains($0.url) },
                      summary: summary.joined(separator: "\n"))
    }

    /// Yapay zekâya gidecek tek satırlık özet.
    private func describe(_ post: SocialExport.Post) async -> String {
        var parts: [String] = []
        switch post.source {
        case .tiktok:
            if let video = await TikTokOEmbed.video(for: post.url) {
                parts.append("TikTok video by @\(video.author ?? post.author ?? "?"): \(video.title)")
            } else {
                parts.append("TikTok video" + (post.author.map { " by @\($0)" } ?? ""))
            }
        default:
            parts.append("Instagram post" + (post.author.map { " from account @\($0)" } ?? ""))
        }
        if let collection = post.collection {
            parts.append("saved in collection \"\(collection)\"")
        }
        return parts.joined(separator: ", ")
    }
}

/// TikTok'un herkese açık, anahtarsız resmi oEmbed servisi: video
/// açıklaması ve hesap adı (developers.tiktok.com/doc/embed-videos).
enum TikTokOEmbed {
    struct Video: Decodable {
        var title: String
        var author: String?

        enum CodingKeys: String, CodingKey {
            case title
            case author = "author_unique_id"
        }
    }

    static func video(for url: URL) async -> Video? {
        var link = url
        // Kısa linkler (vm.tiktok.com) önce tam adrese çevrilir.
        if let host = url.host, host.hasPrefix("vm.") || host.hasPrefix("vt."),
           let fetched = try? await URLSession.shared.data(from: url), let full = fetched.1.url {
            link = full
        }
        var candidates = [link]
        if let id = SocialExport.tiktokVideoID(in: link),
           let canonical = URL(string: "https://www.tiktok.com/@tiktok/video/\(id)") {
            candidates.append(canonical)
        }
        for candidate in candidates {
            var components = URLComponents(string: "https://www.tiktok.com/oembed")
            components?.queryItems = [URLQueryItem(name: "url", value: candidate.absoluteString)]
            guard let api = components?.url,
                  let result = try? await URLSession.shared.data(from: api),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let video = try? JSONDecoder().decode(Video.self, from: result.0),
                  !video.title.isEmpty
            else { continue }
            return video
        }
        return nil
    }
}

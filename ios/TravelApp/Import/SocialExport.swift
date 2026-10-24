import Foundation

/// Instagram ve TikTok "verilerini indir" dosyalarındaki kaydedilen
/// gönderiler. Dosyalarda yer bilgisi yok; yalnızca gönderi linki, hesap
/// adı ve (Instagram'da) koleksiyon adı var. İnternete çıkmaz.
///
/// - Instagram (JSON ya da HTML): `saved_posts`, `saved_collections`.
/// - TikTok (JSON ya da TXT): "Favorite Videos" (Favoriler) bölümü.
///
/// Biçimler zamanla değiştiği için alan adlarına sıkı bağlı değiliz:
/// dosya taranır, kayıt/favori bölümündeki gönderi linkleri toplanır.
enum SocialExport {
    struct Post: Codable, Hashable, Identifiable {
        var url: URL
        var source: PlaceSource
        var author: String?
        var collection: String?

        var id: String { url.absoluteString }
    }

    static func parse(data: Data, fileName: String) -> [Post] {
        let text = String(decoding: data, as: UTF8.self)
        var posts: [Post] = []
        if let json = try? JSONSerialization.jsonObject(with: data) {
            walk(json, path: fileName.lowercased(), collection: nil, into: &posts)
        } else if isSavedSection(fileName.lowercased()) {
            // HTML ya da TXT: yalnızca kayıt/favori dosyasındaki linkler.
            for url in links(in: text) {
                posts.append(Post(url: url, source: source(of: url)))
            }
        } else {
            posts = favoritesFromText(text)
        }
        var seen = Set<String>()
        return posts.filter { seen.insert(canonical($0.url)).inserted }
    }

    // MARK: - JSON

    private static func walk(_ node: Any, path: String, collection: String?, into posts: inout [Post]) {
        if let array = node as? [Any] {
            var current = collection
            for element in array {
                // Instagram koleksiyon dosyasında koleksiyon başlığı, ardından
                // o koleksiyonun gönderileri gelir.
                if let header = collectionHeader(element) {
                    current = header
                    continue
                }
                walk(element, path: path, collection: current, into: &posts)
            }
            return
        }
        guard let dictionary = node as? [String: Any] else { return }

        // Tek gönderilik kayıt: içinde tek bir gönderi linki olan sözlük.
        if isSavedSection(path) {
            let strings = allStrings(in: dictionary)
            let urls = strings.compactMap { post(from: $0.value) }
            if let url = urls.first, Set(urls.map(canonical)).count == 1 {
                posts.append(Post(url: url, source: source(of: url),
                                  author: author(in: dictionary, strings: strings), collection: collection))
                return
            }
        }
        for (key, value) in dictionary {
            walk(value, path: path + "/" + key.lowercased(), collection: collection, into: &posts)
        }
    }

    /// Instagram: {"string_map_data": {"Name": {"value": "Tokyo"}, "Creation Time": ...}}
    /// gibi, gönderi linki olmayan bir koleksiyon başlığı.
    private static func collectionHeader(_ node: Any) -> String? {
        guard let dictionary = node as? [String: Any],
              let map = dictionary["string_map_data"] as? [String: Any],
              map.keys.contains(where: { $0.lowercased().contains("creation") }),
              let name = (map["Name"] as? [String: Any])?["value"] as? String,
              !allStrings(in: dictionary).contains(where: { post(from: $0.value) != nil })
        else { return nil }
        return name
    }

    private static func author(in dictionary: [String: Any], strings: [(key: String, value: String)]) -> String? {
        if let title = dictionary["title"] as? String, !title.isEmpty, post(from: title) == nil {
            return title
        }
        for key in ["username", "author", "owner", "name"] {
            let match = strings.first { pair in
                pair.key.lowercased() == key && !pair.value.isEmpty && URL(string: pair.value)?.scheme == nil
            }
            if let match { return match.value }
        }
        return nil
    }

    /// Sözlükteki bütün metinler; "label_values" biçiminde etiket anahtar sayılır.
    private static func allStrings(in node: Any, key: String = "") -> [(key: String, value: String)] {
        if let string = node as? String { return [(key, string)] }
        if let array = node as? [Any] { return array.flatMap { allStrings(in: $0, key: key) } }
        guard let dictionary = node as? [String: Any] else { return [] }
        if let label = dictionary["label"] as? String, let value = dictionary["value"] as? String {
            return [(label, value)]
        }
        var result: [(key: String, value: String)] = []
        for (childKey, value) in dictionary {
            // {"Name": {"value": "x", "href": "..."}} gibi iç içe değerler
            // dış anahtarın adını taşır.
            let name = (childKey == "value" || childKey == "href") ? key : childKey
            result += allStrings(in: value, key: name)
        }
        return result
    }

    // MARK: - TXT (TikTok)

    /// TikTok TXT dosyasında "Favorite Videos" başlığından sonraki linkler,
    /// bir sonraki başlığa kadar.
    private static func favoritesFromText(_ text: String) -> [Post] {
        var inFavorites = false
        var posts: [Post] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            let isHeader = !trimmed.isEmpty && !lower.hasPrefix("date") && !lower.hasPrefix("link")
                && !lower.contains("http") && trimmed.hasSuffix(":")
            if isHeader {
                inFavorites = isSavedSection(lower)
                continue
            }
            if inFavorites {
                for url in links(in: trimmed) {
                    posts.append(Post(url: url, source: source(of: url)))
                }
            }
        }
        return posts
    }

    // MARK: - Linkler

    /// Kayıt/favori bölümü mü? (Beğeniler ve izleme geçmişi alınmaz.)
    static func isSavedSection(_ path: String) -> Bool {
        let lower = path.lowercased()
        // TikTok beğenileri "Like List/ItemFavoriteList" altında; alınmaz.
        if lower.contains("like") { return false }
        return lower.contains("saved") || lower.contains("favorite") || lower.contains("favourite")
            || lower.contains("collection") || lower.contains("kaydedil") || lower.contains("favori")
    }

    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url.flatMap(post(from:)) }
    }

    /// Instagram gönderisi/reels ya da TikTok videosu linki.
    static func post(from string: String) -> URL? {
        post(from: URL(string: string.trimmingCharacters(in: .whitespaces)))
    }

    private static func post(from url: URL?) -> URL? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if host.hasSuffix("instagram.com"),
           path.hasPrefix("/p/") || path.hasPrefix("/reel/") || path.hasPrefix("/reels/") || path.hasPrefix("/tv/") {
            return url
        }
        if host.contains("tiktok"), path.contains("/video/") || host.hasPrefix("vm.") || host.hasPrefix("vt.") {
            return url
        }
        return nil
    }

    static func source(of url: URL) -> PlaceSource {
        url.host?.lowercased().contains("tiktok") == true ? .tiktok : .instagram
    }

    /// TikTok video numarası (…/video/7212345678901234567).
    static func tiktokVideoID(in url: URL) -> String? {
        let parts = url.path.split(separator: "/")
        guard let index = parts.firstIndex(of: "video"), parts.indices.contains(index + 1) else { return nil }
        let id = parts[index + 1]
        return id.allSatisfy(\.isNumber) ? String(id) : nil
    }

    /// Aynı gönderinin farklı yazılışları için ortak anahtar.
    static func canonical(_ url: URL) -> String {
        if let id = tiktokVideoID(in: url) { return "tiktok:\(id)" }
        let parts = url.path.split(separator: "/")
        if parts.count >= 2 { return "instagram:\(parts[1])" }
        return url.absoluteString
    }
}

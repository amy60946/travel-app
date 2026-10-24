import Foundation

/// Kullanıcının indirdiği veri dosyaları (Instagram, TikTok, Google
/// Takeout). .zip'i uygulama kendisi açar ve içinden yalnızca kayıtlı yer
/// ve gönderi dosyalarını alır; mesajlar, fotoğraflar vb. okunmaz.
enum ExportFiles {
    struct File {
        let name: String
        let data: Data
    }

    /// Instagram'ın "Bilgilerini dışa aktar" sayfası (Meta'nın resmi bağlantısı).
    static let instagramExportPage = URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi")!

    /// Dosyaları okur, .zip'leri açar. Yavaş olabilir; ana iş parçacığında çağırma.
    static func load(_ urls: [URL]) -> [File] {
        urls.flatMap { url -> [File] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = read(url) else { return [] }
            return files(in: data, name: url.lastPathComponent)
        }
    }

    /// Bir dosyanın içindekiler: .zip ise içindeki ilgili dosyalar, değilse kendisi.
    static func files(in data: Data, name: String) -> [File] {
        let isZip = name.lowercased().hasSuffix(".zip") || data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        guard isZip else { return [File(name: name, data: data)] }
        guard let zip = ZipReader(data: data) else { return [] }
        return zip.entries
            .filter { isRelevant($0.path) && $0.size <= 100_000_000 }
            .compactMap { entry in zip.contents(of: entry).map { File(name: entry.path, data: $0) } }
    }

    /// .zip içinde okumaya değer dosya: kaydedilenler, favoriler,
    /// koleksiyonlar ve Google Haritalar listeleri.
    static func isRelevant(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard ["json", "csv", "txt", "html"].contains((lower as NSString).pathExtension) else { return false }
        if lower.contains("message") || lower.contains("inbox") { return false }
        return ["saved", "favorite", "favourite", "collection", "user_data", "maps", "places"]
            .contains { lower.contains($0) }
    }

    /// Dosya adı bir veri dosyasına benziyor mu: instagram-…zip,
    /// TikTok_Data_…zip, user_data_tiktok.json, takeout-…zip.
    static func isExportName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard ["zip", "json", "txt"].contains((lower as NSString).pathExtension) else { return false }
        return lower.hasPrefix("instagram") || lower.contains("tiktok")
            || lower.hasPrefix("user_data") || lower.hasPrefix("takeout")
    }

    /// iCloud'da duran dosyayı da indirip okur.
    private static func read(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            result = try? Data(contentsOf: readURL, options: .mappedIfSafe)
        }
        return result ?? (try? Data(contentsOf: url, options: .mappedIfSafe))
    }
}

/// Kullanıcının bir kez izin verdiği klasör (ör. İndirilenler). Uygulama
/// oraya inen en yeni veri dosyasını kendisi bulur ve aktarılanları hatırlar.
enum ExportFolder {
    struct Found {
        let name: String
        let identity: String
        let files: [ExportFiles.File]
    }

    private static let bookmarkKey = "exportFolderBookmark"
    private static let seenKey = "importedExportFiles"
    /// Bundan eski dosyalar "yeni indirilen" sayılmaz.
    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    static var isLinked: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    static var folderName: String? { resolve()?.lastPathComponent }

    /// Seçilen klasörü hatırlar; başarısızsa false.
    static func link(_ folder: URL) -> Bool {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? folder.bookmarkData() else { return false }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        return true
    }

    /// Henüz aktarılmamış yeni bir veri dosyası var mı (yalnızca listeye bakar).
    static func hasNew() -> Bool {
        withFolder { candidates(in: $0).first != nil } ?? false
    }

    /// En yeni, henüz aktarılmamış veri dosyasını bulur ve okur. Yavaş olabilir.
    static func loadNewest() -> Found? {
        withFolder { folder -> Found? in
            guard let newest = candidates(in: folder).first else { return nil }
            let files = ExportFiles.load([newest.url])
            return Found(name: newest.url.lastPathComponent, identity: newest.identity, files: files)
        } ?? nil
    }

    /// Dosya bir daha aktarılmasın.
    static func markSeen(_ found: Found) {
        var seen = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        seen.append(found.identity)
        UserDefaults.standard.set(Array(seen.suffix(100)), forKey: seenKey)
    }

    private struct Candidate {
        let url: URL
        let identity: String
        let date: Date
    }

    /// Klasördeki yeni veri dosyaları, en yenisi önce.
    private static func candidates(in folder: URL) -> [Candidate] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        let seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let cutoff = Date().addingTimeInterval(-maxAge)
        return urls.compactMap { url -> Candidate? in
            guard ExportFiles.isExportName(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys),
                  let date = values.contentModificationDate, date > cutoff else { return nil }
            let identity = "\(url.lastPathComponent)|\(values.fileSize ?? 0)|\(Int(date.timeIntervalSince1970))"
            return seen.contains(identity) ? nil : Candidate(url: url, identity: identity, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    private static func withFolder<T>(_ body: (URL) -> T) -> T? {
        guard let folder = resolve() else { return nil }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return body(folder)
    }

    private static func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { _ = link(folder) }
        return folder
    }
}

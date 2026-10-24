import Foundation

/// Telefonda dosya olarak duran küçük anahtar-değer önbelleği. İndirilen
/// anlatımlar ve rotalar internetsiz yürüyüşte buradan okunur.
final class DiskCache<Value: Codable> {
    private let url: URL
    private var storage: [String: Value]

    init(name: String) {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TravelApp/Cache/\(name).json")
        storage = (try? JSONDecoder().decode([String: Value].self, from: Data(contentsOf: url))) ?? [:]
    }

    subscript(key: String) -> Value? {
        get { storage[key] }
        set {
            storage[key] = newValue
            save()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(storage).write(to: url, options: .atomic)
    }
}

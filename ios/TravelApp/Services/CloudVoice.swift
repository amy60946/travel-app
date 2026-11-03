import CryptoKit
import Foundation

/// Anlatımın Google sesi (Cloud Text-to-Speech, Chirp 3 HD): insan sesine
/// yakın, doğal Türkçe ve İngilizce. Yalnızca aylık ücretsiz kota (1 milyon
/// harf) kullanılır; telefon başına günde ve ayda harf sınırı var
/// (`VoiceAllowance`). Her parçanın sesi bir kez üretilip telefonda
/// saklanır: aynı yazı yeniden dinlenince istek gitmez, kotadan düşmez.
/// Anahtar yoksa, sınır dolduysa, internet yoksa ya da Google cevap
/// vermezse anlatım iPhone sesiyle sürer (Oguz'un 2026-11-03 kararı).
@MainActor
final class CloudVoice {
    static let shared = CloudVoice()

    /// Chirp 3 HD sesinin adı; Türkçe ve İngilizcede aynı ses.
    static let voiceName = "Aoede"

    private let defaults: UserDefaults
    private var inFlight: [String: Task<URL?, Never>] = [:]
    /// Google "kapalı", "izin yok" ya da "böyle ses yok" dediyse uygulama
    /// açıkken yeniden denenmez (her parçada boşuna beklenmesin).
    private var disabled = false
    private var trimmed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Yeni bir anlatım Google sesiyle başlayabilir mi.
    var isAvailable: Bool {
        GoogleAPI.isConfigured && !disabled && !Self.skipsForScreenshot
            && VoiceAllowance(defaults: defaults).remaining(now: Date()) > 0
    }

    /// Yazının sesi (MP3 dosyası). Telefonda varsa hemen, yoksa Google'dan
    /// üretilir. Olmazsa nil: anlatım iPhone sesine geçer.
    func audioFile(for text: String, language: String) async -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let voice = Self.voice(for: language)
        let file = Self.cacheFile(text: text, voice: voice.name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let key = file.lastPathComponent
        if let running = inFlight[key] { return await running.value }
        let task = Task { await self.synthesize(text, voice: voice, to: file) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func synthesize(_ text: String, voice: (language: String, name: String), to file: URL) async -> URL? {
        guard !disabled, !Self.skipsForScreenshot else { return nil }
        let allowance = VoiceAllowance(defaults: defaults)
        let count = text.count
        guard allowance.remaining(now: Date()) >= count,
              let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize"),
              let request = try? GoogleAPI.request(url, body: [
                  "input": ["text": text],
                  "voice": ["languageCode": voice.language, "name": voice.name],
                  "audioConfig": ["audioEncoding": "MP3"],
              ]) else { return nil }
        struct Response: Decodable { var audioContent: String }
        do {
            let response = try await GoogleAPI.fetch(Response.self, request)
            guard let data = Data(base64Encoded: response.audioContent), !data.isEmpty else { return nil }
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            allowance.record(count, now: Date())
            trimOnce()
            return file
        } catch GoogleAPI.Failure.http(let status) where [400, 401, 403, 404].contains(status) {
            disabled = true
            return nil
        } catch {
            return nil
        }
    }

    /// "tr-TR-Chirp3-HD-Aoede" gibi.
    static func voice(for language: String) -> (language: String, name: String) {
        let code = language == "tr" ? "tr-TR" : "en-US"
        return (code, "\(code)-Chirp3-HD-\(voiceName)")
    }

    static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Narration", isDirectory: true)

    /// Aynı ses ve yazı her zaman aynı dosya.
    static func cacheFile(text: String, voice: String) -> URL {
        let digest = SHA256.hash(data: Data("\(voice)|\(text)".utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("mp3")
    }

    /// Kayıtlı sesler 300 MB'ı geçerse en eski dinlenenler silinir
    /// (iPhone da yer daralınca bu klasörü kendisi boşaltabilir).
    private func trimOnce() {
        guard !trimmed else { return }
        trimmed = true
        let directory = Self.directory
        Task.detached(priority: .background) {
            Self.trim(directory, maxBytes: 300_000_000)
        }
    }

    nonisolated static func trim(_ directory: URL, maxBytes: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { file -> (url: URL, size: Int, used: Date)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.fileSize ?? 0, values.contentAccessDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.used < $1.used }) where total > maxBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Ekran görüntüsü açılışları (yalnızca geliştirme sürümü) kotayı harcamasın.
    private static var skipsForScreenshot: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "screen") != nil
        #else
        return false
        #endif
    }
}

/// Google sesinin harf sınırı, telefon başına. Google'ın ücretsiz kotası
/// ayda 1 milyon harf; bir telefon ayda en çok 900.000, günde en çok
/// 60.000 harf (yaklaşık 1 saatlik ses) ister. Telefonda saklanan sesler sayılmaz.
struct VoiceAllowance {
    static let dailyLimit = 60_000
    static let monthlyLimit = 900_000

    let defaults: UserDefaults
    var daily = Self.dailyLimit
    var monthly = Self.monthlyLimit

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Bugün daha kaç harf istenebilir.
    func remaining(now: Date) -> Int {
        let keys = Self.keys(now)
        let today = daily - defaults.integer(forKey: keys.day)
        let thisMonth = monthly - defaults.integer(forKey: keys.month)
        return max(0, min(today, thisMonth))
    }

    func record(_ count: Int, now: Date) {
        let keys = Self.keys(now)
        defaults.set(defaults.integer(forKey: keys.day) + count, forKey: keys.day)
        defaults.set(defaults.integer(forKey: keys.month) + count, forKey: keys.month)
    }

    static func keys(_ date: Date) -> (day: String, month: String) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let month = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        return ("cloudVoice|day|\(month)-" + String(format: "%02d", parts.day ?? 0), "cloudVoice|month|\(month)")
    }
}

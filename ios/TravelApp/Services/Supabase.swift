import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// Gezi paylaşımı ve profil için sunucu (Oguz, 2026-11-02: Supabase ücretsiz
/// katmanı, bu projeye ayrı açılan yeni proje). Adres ve herkese açık
/// ("anon") anahtar GitHub Secrets'tan derleme sırasında gelir
/// (`SUPABASE_URL`, `SUPABASE_ANON_KEY`); yoksa paylaşım bölümleri görünmez.
/// Satırlara kimin erişeceğini veritabanındaki kurallar belirler
/// (supabase/migrations).
enum Supabase {
    static let url: URL? = {
        guard let text = infoValue("SupabaseURL"), let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }()

    static let anonKey: String? = infoValue("SupabaseAnonKey")

    static var isConfigured: Bool {
        #if DEBUG
        // Ekran görüntülerinde paylaşım bölümleri örnek verilerle görünür.
        if Account.demoScreen != nil { return true }
        #endif
        return url != nil && anonKey != nil
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    enum Failure: LocalizedError {
        case notConfigured
        case signedOut
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: "Paylaşım bu sürümde kapalı.")
            case .signedOut: String(localized: "Önce giriş yapmalısın.")
            case .http: String(localized: "Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip yeniden dene.")
            }
        }
    }

    /// Sunucuya istek: `path` "rest/v1/shared_trips" gibi. `token` verilmezse
    /// herkese açık anahtarla (giriş yapmamış biri gibi) gider.
    static func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], json: Any? = nil,
                        token: String? = nil, prefer: String? = nil) throws -> URLRequest {
        guard let url, let anonKey else { throw Failure.notConfigured }
        var components = URLComponents(url: url.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let target = components?.url else { throw Failure.notConfigured }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        // Girişliyken kullanıcının anahtarı. Girişsizken yalnızca eski tür
        // (JWT, "eyJ…") anahtar bu başlığa da konur; yeni tür
        // ("sb_publishable_…") yalnızca `apikey` başlığında gider (Supabase belgesi).
        if let bearer = token ?? (anonKey.hasPrefix("eyJ") ? anonKey : nil) {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    /// İsteği gönderir; 2xx dışında hata verir.
    @discardableResult
    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.http(status, String(data: data.prefix(500), encoding: .utf8) ?? "")
        }
        return data
    }

    static var decoder: JSONDecoder { JSONDecoder() }
}

/// Giriş (Apple ile) ve profil. Oturum anahtarları iPhone'un anahtar
/// zincirinde (Keychain) durur; profil adı ve simgesi sunucuda.
@MainActor
final class Account: ObservableObject {
    static let shared = Account()

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: UUID
        /// "apple" ya da "google" (Profil'de "… ile giriş yapıldı").
        var provider: String?
    }

    struct Profile: Codable, Equatable, Hashable {
        var id: UUID
        var name: String
        var emoji: String
    }

    @Published private(set) var session: Session?
    @Published private(set) var profile: Profile?
    /// Supabase'te Google ile giriş açık mı (açılınca düğme kendiliğinden görünür).
    @Published private(set) var googleEnabled = false

    var isSignedIn: Bool { session != nil }
    var userID: UUID? { session?.userID }

    /// Apple'a gönderilen tek kullanımlık sayı (girişin bu uygulamadan
    /// başlatıldığını sunucu doğrular).
    private var nonce: String?
    /// Google ile girişte tarayıcıya verilen kodun gizli eşi (PKCE).
    private var codeVerifier: String?
    private var providersLoaded = false
    private var refreshing: Task<Session, Error>?

    private static let profileKey = "account.profile"

    init() {
        #if DEBUG
        if let screen = Self.demoScreen {
            if Self.signedInDemoScreens.contains(screen) {
                let id = UUID(uuidString: "0B6E1F3C-6A2D-4C34-9E43-9D2B2C0F7A11")!
                session = Session(accessToken: "", refreshToken: "", expiresAt: .distantFuture, userID: id,
                                  provider: "apple")
                profile = Profile(id: id, name: "Oguz", emoji: "🧭")
            }
            return
        }
        #endif
        session = Keychain.load(Session.self)
        if session != nil, let data = UserDefaults.standard.data(forKey: Self.profileKey) {
            profile = try? JSONDecoder().decode(Profile.self, from: data)
        }
    }

    // MARK: - Apple ile giriş

    /// "Apple ile giriş" düğmesine basınca: ad ve e-posta istenir (Supabase
    /// e-postasız girişi kabul etmez; kullanıcı Apple'da "E-postamı gizle"yi
    /// seçebilir), tek kullanımlık sayı eklenir.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let raw = Self.randomNonce()
        nonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(raw)
    }

    /// Apple'ın cevabı: kimlik belgesi Supabase'e verilir, oturum açılır;
    /// profil yoksa Apple'daki adla oluşturulur. Vazgeçilirse sessizce döner.
    func complete(_ result: Result<ASAuthorization, Error>) async throws {
        let authorization: ASAuthorization
        switch result {
        case .success(let value): authorization = value
        case .failure(let error):
            if let error = error as? ASAuthorizationError, error.code == .canceled { return }
            throw error
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8),
              let nonce else { throw Supabase.Failure.signedOut }
        let request = try Supabase.request("auth/v1/token", method: "POST",
                                           query: [URLQueryItem(name: "grant_type", value: "id_token")],
                                           json: ["provider": "apple", "id_token": idToken, "nonce": nonce])
        let (session, _) = try Self.session(from: try await Supabase.send(request))
        self.nonce = nil
        store(session)
        // Apple adı yalnızca ilk girişte verir.
        let given = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        try await loadProfile(defaultName: given)
    }

    // MARK: - Google ile giriş

    /// Uygulamaya dönüş adresi (Supabase → URL Configuration → Redirect URLs'te kayıtlı olmalı).
    static let callbackScheme = "io.travelapp.ios"
    private static let callbackURL = "io.travelapp.ios://auth-callback"

    /// Supabase'te hangi giriş yolları açık (Google düğmesi yalnızca açıksa görünür).
    func loadProviders() async {
        #if DEBUG
        if Self.demoScreen != nil { googleEnabled = true; return }
        #endif
        guard !providersLoaded, let request = try? Supabase.request("auth/v1/settings"),
              let data = try? await Supabase.send(request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let external = object["external"] as? [String: Any] else { return }
        providersLoaded = true
        googleEnabled = external["google"] as? Bool == true
    }

    /// Google giriş sayfasının adresi (Supabase üzerinden; uygulamada Google
    /// anahtarı yok). Tarayıcı penceresinde açılır, bitince
    /// `completeGoogle(_:)` dönüş adresiyle çağrılır.
    func googleSignInURL() throws -> URL {
        guard let base = Supabase.url else { throw Supabase.Failure.notConfigured }
        let verifier = Self.randomNonce() + Self.randomNonce()
        codeVerifier = verifier
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents(url: base.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.callbackURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        guard let url = components?.url else { throw Supabase.Failure.notConfigured }
        return url
    }

    /// Google'dan dönüş: adresteki kod oturuma çevrilir; profil yoksa
    /// Google'daki adla oluşturulur.
    func completeGoogle(_ callback: URL) async throws {
        var items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = callback.fragment {
            items += URLComponents(string: "?" + fragment)?.queryItems ?? []
        }
        if let message = items.first(where: { $0.name == "error_description" || $0.name == "error" })?.value {
            throw Supabase.Failure.http(400, message)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, let verifier = codeVerifier else {
            throw Supabase.Failure.signedOut
        }
        let request = try Supabase.request("auth/v1/token", method: "POST",
                                           query: [URLQueryItem(name: "grant_type", value: "pkce")],
                                           json: ["auth_code": code, "code_verifier": verifier])
        let (session, name) = try Self.session(from: try await Supabase.send(request))
        codeVerifier = nil
        store(session)
        try await loadProfile(defaultName: name ?? "")
    }

    func signOut() async {
        if let session {
            if let request = try? Supabase.request("auth/v1/logout", method: "POST", token: session.accessToken) {
                _ = try? await Supabase.send(request)
            }
        }
        clear()
    }

    /// Hesabı ve sunucudaki her şeyi (profil, paylaşılan geziler) siler.
    /// Telefondaki geziler ve kayıtlar yerinde kalır.
    func deleteAccount() async throws {
        let token = try await validToken()
        try await Supabase.send(try Supabase.request("rest/v1/rpc/delete_my_account", method: "POST",
                                                     json: [String: String](), token: token))
        clear()
    }

    // MARK: - Profil

    /// Sunucudaki profil; yoksa oluşturulur (ad Apple'dan ya da "Gezgin").
    func loadProfile(defaultName: String = "") async throws {
        guard let userID else { throw Supabase.Failure.signedOut }
        let token = try await validToken()
        let request = try Supabase.request("rest/v1/profiles", query: [
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "id,name,emoji"),
        ], token: token)
        let found = try Supabase.decoder.decode([Profile].self, from: try await Supabase.send(request)).first
        if let found {
            setProfile(found)
        } else {
            let name = defaultName.isEmpty ? String(localized: "Gezgin") : defaultName
            try await saveProfile(name: name, emoji: "🧭")
        }
    }

    func saveProfile(name: String, emoji: String) async throws {
        guard let userID else { throw Supabase.Failure.signedOut }
        let token = try await validToken()
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let emoji = emoji.isEmpty ? "🧭" : String(emoji.prefix(1))
        let request = try Supabase.request("rest/v1/profiles", method: "POST", json: [[
            "id": userID.uuidString.lowercased(), "name": name, "emoji": emoji,
        ]], token: token, prefer: "resolution=merge-duplicates,return=representation")
        let saved = try Supabase.decoder.decode([Profile].self, from: try await Supabase.send(request)).first
        setProfile(saved ?? Profile(id: userID, name: name, emoji: emoji))
    }

    // MARK: - Oturum

    /// Geçerli erişim anahtarı; süresi dolmak üzereyse yenilenir.
    func validToken() async throws -> String {
        guard let session else { throw Supabase.Failure.signedOut }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        let task = Task { () throws -> Session in
            let request = try Supabase.request("auth/v1/token", method: "POST",
                                               query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                               json: ["refresh_token": session.refreshToken])
            return try Self.session(from: try await Supabase.send(request)).0
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            store(fresh)
            return fresh.accessToken
        } catch Supabase.Failure.http(let status, _) where (400..<500).contains(status) {
            // Yenileme anahtarı geçersiz (ör. hesap başka yerden silindi): çıkış.
            clear()
            throw Supabase.Failure.signedOut
        }
    }

    private func store(_ session: Session) {
        self.session = session
        Keychain.save(session)
    }

    private func setProfile(_ profile: Profile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.profileKey)
        }
    }

    private func clear() {
        session = nil
        profile = nil
        Keychain.delete()
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
        TripSharing.shared.forgetLocalState()
    }

    /// Sunucunun oturum cevabı; yanında giriş yapılan hesaptaki ad (Google verir).
    private static func session(from data: Data) throws -> (Session, String?) {
        struct Response: Decodable {
            struct User: Decodable {
                struct AppMetadata: Decodable { let provider: String? }
                struct UserMetadata: Decodable {
                    let full_name: String?
                    let name: String?
                }
                let id: UUID
                let app_metadata: AppMetadata?
                let user_metadata: UserMetadata?
            }
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let user: User
        }
        let response = try Supabase.decoder.decode(Response.self, from: data)
        let session = Session(accessToken: response.access_token, refreshToken: response.refresh_token,
                              expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600),
                              userID: response.user.id, provider: response.user.app_metadata?.provider)
        let name = response.user.user_metadata?.full_name ?? response.user.user_metadata?.name
        return (session, name)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
    /// Ekran görüntüsü açılışı (`-screen …`), varsa.
    nonisolated static var demoScreen: String? {
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        return demoScreens.contains(screen) ? screen : nil
    }
    /// Paylaşım ekranlarının görüntüleri (örnek verilerle, internetsiz).
    nonisolated static let demoScreens: Set<String> = [
        "profile", "profileShared", "shareTrip", "editProfile", "discover", "discoverTall", "sharedTrip",
        "traveler", "searchTrips",
    ]
    /// Bu ekranlarda örnek bir hesapla girilmiş görünür.
    nonisolated static let signedInDemoScreens: Set<String> = ["profileShared", "shareTrip", "editProfile"]
    #endif
}

/// Oturum anahtarlarının iPhone'daki kasası (Keychain).
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.travelapp.supabase",
        kSecAttrAccount as String: "session",
    ]

    static func save<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load<T: Decodable>(_ type: T.Type) -> T? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

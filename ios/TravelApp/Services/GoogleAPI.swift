import Foundation
import GoogleMaps

/// Google Haritalar hesabı (Oguz, 2026-10-29: kartlı hesap, aylık ücretsiz
/// kotalar ve günlük üst sınırlar). Anahtar GitHub Secrets'tan derleme
/// sırasında gelir (`GOOGLE_MAPS_API_KEY`) ve Google Cloud'da yalnızca bu
/// uygulamaya (io.travelapp.ios) kilitlidir.
enum GoogleAPI {
    static let apiKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }()

    static var isConfigured: Bool { apiKey != nil }

    /// Uygulama açılırken bir kez. Anahtar yoksa da bir değer verilir;
    /// verilmezse harita açılırken uygulama kapanır (harita boş görünür).
    static func configure() {
        GMSServices.provideAPIKey(apiKey ?? "anahtar-yok")
    }

    /// Google'dan gelen yazıların dili: uygulamanın dili.
    static var language: String { AppLanguage.current.rawValue }

    enum Failure: Error {
        case notConfigured
        case http(Int)
    }

    /// Places ve Routes istekleri: anahtar, istenen alanlar ve uygulamanın
    /// kimliği (anahtar uygulamaya kilitli olduğu için gerekli).
    static func request(_ url: URL, fields: String? = nil, body: [String: Any]? = nil) throws -> URLRequest {
        guard let apiKey else { throw Failure.notConfigured }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Bundle.main.bundleIdentifier ?? "io.travelapp.ios", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        if let fields { request.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func fetch<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Google'ın kısaltılmış çizgi biçimini (encoded polyline) noktalara açar.
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        func next() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }
        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            latitude += dLat
            longitude += dLon
            coordinates.append(CLLocationCoordinate2D(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
        }
        return coordinates
    }
}

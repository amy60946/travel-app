import CoreLocation
import UIKit

/// Tabelada okunur yazı yoksa fotoğrafı Google Gemini'ye (ücretsiz katman)
/// gönderip yerin adını sorar. Anahtar GitHub Secrets'tan derleme sırasında
/// gelir (`GEMINI_API_KEY`); yoksa bu yol kapalıdır.
enum GeminiVision {
    private static let model = "gemini-flash-latest"

    static var apiKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    static var isAvailable: Bool { apiKey != nil }

    /// Fotoğraftaki yer için en olası adlar (en fazla 3).
    static func placeNames(in image: UIImage, near location: CLLocation) async -> [String] {
        guard let apiKey, let jpeg = resized(image, maxSide: 1024).jpegData(compressionQuality: 0.7),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        else { return [] }

        let prompt = """
        This photo was taken near latitude \(location.coordinate.latitude), longitude \(location.coordinate.longitude). \
        Identify the specific place shown (shop, restaurant, temple, shrine, museum, landmark or building). \
        Reply only with JSON like {"names": ["most likely name", "second guess"]}, using names as they appear on maps. \
        Use an empty list if you are not sure.
        """
        let body: [String: Any] = [
            "contents": [["parts": [
                ["text": prompt],
                ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ]]],
            "generationConfig": ["responseMimeType": "application/json"],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parseNames(from: result.0)
    }

    /// Gemini cevabındaki metnin içindeki {"names": [...]}.
    static func parseNames(from data: Data) -> [String] {
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { var text: String? }
                    var parts: [Part]
                }
                var content: Content?
            }
            var candidates: [Candidate]?
        }
        struct Names: Decodable { var names: [String] }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.candidates?.first?.content?.parts.compactMap(\.text).joined(),
              let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let names = try? JSONDecoder().decode(Names.self, from: Data(text[start...end].utf8))
        else { return [] }
        return Array(names.names.filter { !$0.isEmpty }.prefix(3))
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

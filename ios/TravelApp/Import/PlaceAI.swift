import CoreLocation
import UIKit

/// Ücretsiz bulut yapay zekâlarıyla (Google Gemini ve Groq) yer adı bulur.
/// Fotoğrafta resim ve telefonun okuduğu yazı birlikte, yapıştırılan
/// yazıda metin gönderilir. Anahtarı olan servislerin hepsi aynı anda
/// sorulur, cevaplar birleştirilir. Anahtarlar GitHub Secrets'tan derleme
/// sırasında gelir (`GEMINI_API_KEY`, `GROQ_API_KEY`); anahtarı olmayan
/// servis kapalıdır.
enum PlaceAI {
    enum Provider: CaseIterable {
        case gemini, groq

        var name: String {
            switch self {
            case .gemini: "Google Gemini"
            case .groq: "Groq"
            }
        }

        fileprivate var infoKey: String {
            switch self {
            case .gemini: "GeminiAPIKey"
            case .groq: "GroqAPIKey"
            }
        }
    }

    /// Bulunan yer: ad ve (biliniyorsa) şehir.
    struct Found: Equatable, Decodable {
        var name: String
        var city: String?
    }

    private static let geminiModel = "gemini-flash-latest"
    /// Groq'ta resim de okuyabilen ücretsiz model (console.groq.com/docs/vision).
    private static let groqModel = "qwen/qwen3.8-27b"

    static func apiKey(for provider: Provider) -> String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: provider.infoKey) as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    static var providers: [Provider] { Provider.allCases.filter { apiKey(for: $0) != nil } }

    static var isAvailable: Bool { !providers.isEmpty }

    /// Fotoğraftaki yer için en olası adlar (en fazla 4).
    static func placeNames(in image: UIImage, readText: [String], near location: CLLocation) async -> [String] {
        guard isAvailable, let jpeg = resized(image, maxSide: 1024).jpegData(compressionQuality: 0.7) else { return [] }
        var prompt = "This photo was taken near latitude \(location.coordinate.latitude), "
            + "longitude \(location.coordinate.longitude). "
        if !readText.isEmpty {
            prompt += "Text read on the photo: \(readText.prefix(8).joined(separator: " | ")). "
        }
        prompt += """
        Identify the specific place shown (shop, restaurant, temple, shrine, museum, landmark or building). \
        Reply only with JSON like {"places": [{"name": "most likely name"}, {"name": "second guess"}]}, \
        using names as they appear on maps. Use an empty list if you are not sure.
        """
        let found = await askAll(prompt: prompt, jpeg: jpeg)
        return found.prefix(4).map(\.name)
    }

    /// Yapıştırılan yazıdaki (ör. Instagram açıklaması, mesaj, liste) yerler.
    static func places(inText text: String) async -> [Found] {
        guard isAvailable else { return [] }
        let prompt = """
        Find every specific place (restaurant, cafe, bar, shop, museum, temple, shrine, park, landmark, hotel) \
        mentioned in the text below. Reply only with JSON like \
        {"places": [{"name": "place name as on maps", "city": "city name or null"}]}. \
        Use an empty list if there are none.

        Text:
        \(text.prefix(4000))
        """
        let found = await askAll(prompt: prompt, jpeg: nil)
        return Array(found.prefix(30))
    }

    /// Yapay zekâ yokken: her kısa satır bir yer adı sayılır.
    static func lines(in text: String) -> [Found] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters)) }
            .filter { $0.count >= 2 && $0.count <= 50 }
        return merge([lines.map { Found(name: $0) }]).prefix(30).map { $0 }
    }

    private static func askAll(prompt: String, jpeg: Data?) async -> [Found] {
        let providers = self.providers
        var lists = Array(repeating: [Found](), count: providers.count)
        await withTaskGroup(of: (Int, [Found]).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await ask(provider, prompt: prompt, jpeg: jpeg)) }
            }
            for await result in group {
                lists[result.0] = result.1
            }
        }
        return merge(lists)
    }

    private static func ask(_ provider: Provider, prompt: String, jpeg: Data?) async -> [Found] {
        guard let key = apiKey(for: provider),
              let request = makeRequest(provider, key: key, prompt: prompt, jpeg: jpeg),
              let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        switch provider {
        case .gemini: return parse(geminiResponse: result.0)
        case .groq: return parse(groqResponse: result.0)
        }
    }

    private static func makeRequest(_ provider: Provider, key: String, prompt: String, jpeg: Data?) -> URLRequest? {
        let urlString: String
        let body: [String: Any]
        switch provider {
        case .gemini:
            urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent"
            var parts: [[String: Any]] = [["text": prompt]]
            if let jpeg {
                parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
            }
            body = [
                "contents": [["parts": parts]],
                "generationConfig": ["responseMimeType": "application/json"],
            ]
        case .groq:
            urlString = "https://api.groq.com/openai/v1/chat/completions"
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let jpeg {
                content.append(["type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]])
            }
            body = [
                "model": groqModel,
                "messages": [["role": "user", "content": content]],
                "response_format": ["type": "json_object"],
                "temperature": 0.2,
            ]
        }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .groq: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return request
    }

    // MARK: - Cevapları okuma

    static func parse(geminiResponse data: Data) -> [Found] {
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
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.candidates?.first?.content?.parts.compactMap(\.text).joined()
        else { return [] }
        return parse(text: text)
    }

    static func parse(groqResponse data: Data) -> [Found] {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            var choices: [Choice]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.choices.first?.message.content
        else { return [] }
        return parse(text: text)
    }

    /// Model metnindeki {"places": [...]} (ya da {"names": [...]}).
    static func parse(text: String) -> [Found] {
        struct Places: Decodable { var places: [Found] }
        struct Names: Decodable { var names: [String] }

        // Düşünme bölümü varsa (<think>…</think>) sonrasına bak.
        var body = Substring(text)
        if let thinkEnd = text.range(of: "</think>") {
            body = text[thinkEnd.upperBound...]
        }
        guard let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}") else { return [] }
        let json = Data(body[start...end].utf8)

        var found: [Found] = []
        if let places = try? JSONDecoder().decode(Places.self, from: json) {
            found = places.places
        } else if let names = try? JSONDecoder().decode(Names.self, from: json) {
            found = names.names.map { Found(name: $0) }
        }
        return found.compactMap { item -> Found? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let city = item.city?.trimmingCharacters(in: .whitespacesAndNewlines)
            let validCity = (city?.isEmpty == false && city?.lowercased() != "null") ? city : nil
            return Found(name: name, city: validCity)
        }
    }

    /// Servislerin listelerini birleştirir: tekrarlar bir kez sayılır,
    /// birden çok servisin bulduğu yer öne geçer, sonra sıra korunur.
    static func merge(_ lists: [[Found]]) -> [Found] {
        var order: [Found] = []
        var votes: [String: Int] = [:]
        let longest = lists.map(\.count).max() ?? 0
        for rank in 0..<longest {
            for list in lists where rank < list.count {
                let key = normalized(list[rank].name)
                guard !key.isEmpty else { continue }
                if votes[key] == nil {
                    order.append(list[rank])
                }
                votes[key, default: 0] += 1
            }
        }
        let ranked = order.enumerated().sorted { (a: (offset: Int, element: Found), b: (offset: Int, element: Found)) -> Bool in
            let votesA = votes[normalized(a.element.name)] ?? 0
            let votesB = votes[normalized(b.element.name)] ?? 0
            if votesA != votesB { return votesA > votesB }
            return a.offset < b.offset
        }
        return ranked.map { $0.element }
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

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

    /// Toplu aramada bir servisin durumu; sonuç ekranında kısaca gösterilir.
    struct Report: Equatable {
        var provider: Provider
        var places = 0
        var requests = 0
        var failures = 0
        /// Son hata (ör. "HTTP 429", "zaman aşımı").
        var error: String?

        mutating func add(_ other: Report) {
            places += other.places
            requests += other.requests
            failures += other.failures
            error = other.error ?? error
        }

        var summary: String {
            if requests > 0, failures == requests {
                return String(localized: "\(provider.name): hata (\(error ?? "?"))")
            }
            if failures > 0 {
                return String(localized: "\(provider.name): \(places) yer, \(failures) istek hata verdi (\(error ?? "?"))")
            }
            return String(localized: "\(provider.name): \(places) yer")
        }
    }

    /// Toplu aramanın sonucu: her gönderi için yerler ve servislerin durumu.
    struct PostResults {
        var places: [[Found]]
        var reports: [Report]
    }

    /// "gemini-flash-latest" 60 sn'de cevap veriyordu (uygulama 30 sn bekliyordu);
    /// bu model aynı cevabı 1-2 sn'de veriyor ve resim de okuyor.
    private static let geminiModel = "gemini-flash-lite-latest"
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

    /// Kaydedilen gönderiler (TikTok açıklaması, Instagram hesap ve koleksiyon
    /// adı) için yerler. Sonuç, gönderilerle aynı sırada ve uzunlukta.
    static func places(inPosts entries: [String]) async -> PostResults {
        let empty = Array(repeating: [Found](), count: entries.count)
        guard isAvailable, !entries.isEmpty else { return PostResults(places: empty, reports: []) }
        var lines: [String] = []
        for (index, entry) in entries.enumerated() {
            lines.append("\(index). \(entry.prefix(600).replacingOccurrences(of: "\n", with: " "))")
        }
        let prompt = """
        Each numbered line below is a social media post a traveller saved: the account that posted it, \
        the traveller's own collection name and, for TikTok, the caption. For each line, list the specific \
        places (restaurant, cafe, bar, shop, museum, temple, shrine, park, landmark, hotel) it refers to. \
        Use the caption when there is one. An account name counts when it is the own account of a venue, \
        a chain or an attraction; ignore personal, blogger, guide and media accounts. For "city" give the \
        place's city; if you do not know it, the city that the collection or account name points to; \
        otherwise null. Reply only with JSON like {"results": [{"index": 0, "places": [{"name": \
        "place name as on maps", "city": "city or null"}]}]}. Leave "places" empty when unsure.

        \(lines.joined(separator: "\n"))
        """
        let providers = self.providers
        var answers = Array(repeating: empty, count: providers.count)
        var reports = providers.map { Report(provider: $0, requests: 1) }
        await withTaskGroup(of: (Int, Reply).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await askText(provider, prompt: prompt, jpeg: nil)) }
            }
            for await (index, reply) in group {
                switch reply {
                case .text(let text):
                    answers[index] = parse(results: text, count: entries.count)
                    reports[index].places = answers[index].reduce(0) { $0 + $1.count }
                case .failure(let error):
                    reports[index].failures = 1
                    reports[index].error = error
                }
            }
        }
        var merged: [[Found]] = []
        for index in entries.indices {
            merged.append(Array(merge(answers.map { $0[index] }).prefix(3)))
        }
        return PostResults(places: merged, reports: reports)
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
        guard case .text(let text) = await askText(provider, prompt: prompt, jpeg: jpeg) else { return [] }
        return parse(text: text)
    }

    /// Bir servisin cevabı: modelin metni ya da kısa hata açıklaması.
    private enum Reply {
        case text(String)
        case failure(String)
    }

    /// Modelin cevap metni. Ücretsiz katmanın dakikalık sınırına takılınca
    /// servisin söylediği kadar bekleyip en fazla iki kez yeniden dener.
    private static func askText(_ provider: Provider, prompt: String, jpeg: Data?) async -> Reply {
        guard let key = apiKey(for: provider),
              let request = makeRequest(provider, key: key, prompt: prompt, jpeg: jpeg)
        else { return .failure(String(localized: "anahtar yok")) }
        for attempt in 1...3 {
            let data: Data
            let response: HTTPURLResponse?
            do {
                let result = try await URLSession.shared.data(for: request)
                data = result.0
                response = result.1 as? HTTPURLResponse
            } catch {
                let timedOut = (error as? URLError)?.code == .timedOut
                return .failure(timedOut ? String(localized: "zaman aşımı") : String(localized: "bağlantı yok"))
            }
            let status = response?.statusCode ?? 0
            if status == 200 {
                let content = provider == .gemini ? text(geminiResponse: data) : text(groqResponse: data)
                return content.map(Reply.text) ?? .failure(String(localized: "boş cevap"))
            }
            let wait = retryDelay(header: response?.value(forHTTPHeaderField: "Retry-After"), body: data)
            guard status == 429 || status == 503, attempt < 3, wait <= 45 else {
                return .failure("HTTP \(status)")
            }
            try? await Task.sleep(for: .seconds(wait))
        }
        return .failure("HTTP 429")
    }

    /// Sınır aşımında beklenecek saniye: "Retry-After" başlığı ya da
    /// Gemini cevabındaki "retryDelay": "23s"; ikisi de yoksa 5 sn.
    static func retryDelay(header: String?, body: Data) -> Double {
        if let header, let seconds = Double(header.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        let text = String(decoding: body, as: UTF8.self)
        if let range = text.range(of: #""retryDelay"\s*:\s*"[0-9.]+s""#, options: .regularExpression),
           let seconds = Double(text[range].filter { $0.isNumber || $0 == "." }) {
            return seconds
        }
        return 5
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
        request.timeoutInterval = 60
        return request
    }

    // MARK: - Cevapları okuma

    static func parse(geminiResponse data: Data) -> [Found] {
        text(geminiResponse: data).map(parse(text:)) ?? []
    }

    static func parse(groqResponse data: Data) -> [Found] {
        text(groqResponse: data).map(parse(text:)) ?? []
    }

    static func text(geminiResponse data: Data) -> String? {
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
        let response = try? JSONDecoder().decode(Response.self, from: data)
        return response?.candidates?.first?.content?.parts.compactMap(\.text).joined()
    }

    static func text(groqResponse data: Data) -> String? {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            var choices: [Choice]
        }
        let response = try? JSONDecoder().decode(Response.self, from: data)
        return response?.choices.first?.message.content
    }

    /// Model metnindeki {"places": [...]} (ya da {"names": [...]}).
    static func parse(text: String) -> [Found] {
        struct Places: Decodable { var places: [Found] }
        struct Names: Decodable { var names: [String] }

        guard let json = jsonBody(in: text) else { return [] }
        if let places = try? JSONDecoder().decode(Places.self, from: json) {
            return cleaned(places.places)
        }
        if let names = try? JSONDecoder().decode(Names.self, from: json) {
            return cleaned(names.names.map { Found(name: $0) })
        }
        return []
    }

    /// Toplu cevaptaki {"results": [{"index": 0, "places": [...]}]}.
    static func parse(results text: String, count: Int) -> [[Found]] {
        struct Results: Decodable {
            struct Entry: Decodable {
                var index: Int
                var places: [Found]?
            }
            var results: [Entry]
        }
        var output = Array(repeating: [Found](), count: count)
        guard let json = jsonBody(in: text),
              let results = try? JSONDecoder().decode(Results.self, from: json) else { return output }
        for entry in results.results where output.indices.contains(entry.index) {
            output[entry.index] = cleaned(entry.places ?? [])
        }
        return output
    }

    /// Metindeki ilk "{" ile son "}" arası. Düşünme bölümü (<think>…</think>)
    /// varsa sonrasına bakılır.
    private static func jsonBody(in text: String) -> Data? {
        var body = Substring(text)
        if let thinkEnd = text.range(of: "</think>") {
            body = text[thinkEnd.upperBound...]
        }
        guard let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end else { return nil }
        return Data(body[start...end].utf8)
    }

    private static func cleaned(_ found: [Found]) -> [Found] {
        found.compactMap { item -> Found? in
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
        // Her servis bir yere en fazla bir oy verir.
        var seen = Array(repeating: Set<String>(), count: lists.count)
        let longest = lists.map(\.count).max() ?? 0
        for rank in 0..<longest {
            for index in lists.indices where rank < lists[index].count {
                let key = normalized(lists[index][rank].name)
                guard !key.isEmpty, !seen[index].contains(key) else { continue }
                seen[index].insert(key)
                if votes[key] == nil {
                    order.append(lists[index][rank])
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

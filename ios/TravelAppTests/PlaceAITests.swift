import XCTest
@testable import TravelApp

final class PlaceAITests: XCTestCase {
    func testParsesGeminiResponse() {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"places\\": [{\\"name\\": \\"Kaminarimon\\"}, {\\"name\\": \\" \\"}]}"}]}}]}
        """
        XCTAssertEqual(PlaceAI.parse(geminiResponse: Data(json.utf8)), [.init(name: "Kaminarimon")])
    }

    func testParsesGroqResponseWithCity() {
        let json = """
        {"choices":[{"message":{"content":"{\\"places\\": [{\\"name\\": \\"Afuri\\", \\"city\\": \\"Tokyo\\"}, {\\"name\\": \\"Blue Bottle\\", \\"city\\": null}]}"}}]}
        """
        XCTAssertEqual(PlaceAI.parse(groqResponse: Data(json.utf8)),
                       [.init(name: "Afuri", city: "Tokyo"), .init(name: "Blue Bottle")])
    }

    func testSkipsThinkingAndAcceptsOldFormat() {
        let text = #"<think>maybe {"x": 1}</think> {"names": ["Sensō-ji"]}"#
        XCTAssertEqual(PlaceAI.parse(text: text), [.init(name: "Sensō-ji")])
    }

    func testBadResponseGivesNothing() {
        XCTAssertEqual(PlaceAI.parse(geminiResponse: Data("{}".utf8)), [])
        XCTAssertEqual(PlaceAI.parse(text: "I am not sure."), [])
    }

    func testMergePutsAgreedPlaceFirstAndDropsDuplicates() {
        let gemini: [PlaceAI.Found] = [.init(name: "Kaminarimon"), .init(name: "Sensō-ji")]
        let groq: [PlaceAI.Found] = [.init(name: "Nakamise"), .init(name: "senso-ji")]
        XCTAssertEqual(PlaceAI.merge([gemini, groq]).map(\.name), ["Sensō-ji", "Kaminarimon", "Nakamise"])
    }

    func testLinesFallback() {
        let text = "Tokyo listem:\n- Afuri\n\n- Afuri\nTeamLab Planets!"
        XCTAssertEqual(PlaceAI.lines(in: text).map(\.name), ["Tokyo listem", "Afuri", "TeamLab Planets"])
    }

    func testDisabledWithoutKeys() {
        // Testlerde anahtar verilmez; bulut yolu kapalı olmalı.
        XCTAssertFalse(PlaceAI.isAvailable)
        XCTAssertTrue(PlaceAI.providers.isEmpty)
    }
}

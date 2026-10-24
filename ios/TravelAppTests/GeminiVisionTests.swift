import XCTest
@testable import TravelApp

final class GeminiVisionTests: XCTestCase {
    func testParsesNamesFromResponse() {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"names\\": [\\"Kaminarimon\\", \\"Sensō-ji\\", \\"\\"]}"}]}}]}
        """
        XCTAssertEqual(GeminiVision.parseNames(from: Data(json.utf8)), ["Kaminarimon", "Sensō-ji"])
    }

    func testBadResponseGivesNoNames() {
        XCTAssertEqual(GeminiVision.parseNames(from: Data("{}".utf8)), [])
        let prose = #"{"candidates":[{"content":{"parts":[{"text":"I am not sure."}]}}]}"#
        XCTAssertEqual(GeminiVision.parseNames(from: Data(prose.utf8)), [])
    }

    func testDisabledWithoutKey() {
        // Testlerde anahtar verilmez; bulut yolu kapalı olmalı.
        XCTAssertFalse(GeminiVision.isAvailable)
    }
}

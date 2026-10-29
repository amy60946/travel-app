import XCTest
@testable import TravelApp

/// Kayıtlı yere Wikipedia sayfası eşleme: emin olunmayan eşleşme yapılmaz.
final class WikipediaMatchTests: XCTestCase {
    func testMatchesSameOrContainedName() {
        XCTAssertTrue(WikipediaService.matches(title: "Sensō-ji", name: "Senso-ji", city: "Tokyo"))
        XCTAssertTrue(WikipediaService.matches(title: "Meiji Shrine", name: "Meiji Tapınağı", city: "Tokyo"))
        XCTAssertTrue(WikipediaService.matches(title: "Galata Tower", name: "Galata Kulesi", city: "İstanbul"))
    }

    func testDoesNotMatchOnGenericOrCityWords() {
        XCTAssertFalse(WikipediaService.matches(title: "Tokyo Skytree", name: "Tokyo Kulesi", city: "Tokyo"))
        XCTAssertFalse(WikipediaService.matches(title: "Ueno Station", name: "Ueno Parkı", city: "Tokyo"))
        XCTAssertFalse(WikipediaService.matches(title: "Zōjō-ji", name: "Blue Bottle Coffee", city: "Tokyo"))
    }
}

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

    func testArticleSectionsSkipReferencesAndKeepSubheadings() {
        let extract = """
        Çırağan Palace is a former Ottoman palace.

        == History ==
        The palace was built by Sultan Abdulaziz.

        === Fire ===
        It burned down in 1910.

        == Architecture ==

        === Interior ===

        == Hotel ==
        Today it is a hotel.

        == References ==
        Some book.
        """
        let sections = WikipediaService.articleSections(fromExtract: extract)
        XCTAssertEqual(sections.map(\.heading), ["History", "Hotel"])
        XCTAssertTrue(sections[0].text.contains("Fire."))
        XCTAssertTrue(sections[0].text.contains("It burned down in 1910."))
        XCTAssertEqual(sections[1].text, "Today it is a hotel.")
    }
}

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

    /// Listedeki fotoğraf yeri anlatmalı: kavşak istasyonla, sokak
    /// istasyonla eşleşmez; yakındaki fotoğraf dosya adında yerin adı
    /// geçiyorsa alınır.
    func testPhotoMatchingRespectsPlaceKind() {
        XCTAssertFalse(WikipediaService.matches(title: "Shibuya Station", name: "Shibuya Kavşağı", city: "Tokyo"))
        XCTAssertTrue(WikipediaService.matches(title: "Shibuya Crossing", name: "Shibuya Kavşağı", city: "Tokyo"))
        XCTAssertTrue(WikipediaService.matches(title: "Takeshita Street", name: "Takeshita Sokağı", city: "Tokyo"))
        XCTAssertFalse(WikipediaService.matches(title: "Harajuku Station", name: "Takeshita Sokağı", city: "Tokyo"))
        XCTAssertTrue(WikipediaService.fileMatches("File:Shibuya Crossing at night.jpg", name: "Shibuya Kavşağı",
                                                   city: "Tokyo"))
        XCTAssertFalse(WikipediaService.fileMatches("File:Tokyo street 2019.jpg", name: "BOHO CO. COFFEE", city: "Tokyo"))
        XCTAssertFalse(WikipediaService.fileMatches("File:Coffee shop in Tokyo.jpg", name: "BOHO CO. COFFEE",
                                                    city: "Tokyo"))
        XCTAssertTrue(WikipediaService.fileMatches("File:Boho coffee Bulgurlu.jpg", name: "BOHO CO. COFFEE",
                                                   city: "İstanbul"))
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

import CoreLocation
import XCTest
@testable import TravelApp

/// "Yakınındaki popüler yerler": günün yerlerine yakın ve bilinen yerler
/// önce; rotadakiler ve 2 km'den uzaklar önerilmez; eklenen yer yerinde kalır.
final class RecommenderTests: XCTestCase {
    private let maidensTower = Place(name: "Kız Kulesi", city: "İstanbul", latitude: 41.02111, longitude: 29.00417,
                                     category: .viewpoint, source: .search)

    private func candidate(_ title: String, _ latitude: Double, _ longitude: Double, views: Int,
                           local: String? = nil) -> WikipediaService.PopularPlace {
        WikipediaService.PopularPlace(title: title, latitude: latitude, longitude: longitude, monthlyViews: views,
                                      thumbnailURL: URL(string: "https://upload.wikimedia.org/x.jpg"), localTitle: local)
    }

    func testNearAndPopularComesFirstFarIsDropped() {
        let candidates = [
            candidate("Şemsi Pasha Mosque", 41.0262, 29.0101, views: 3000),        // ~700 m
            candidate("Mihrimah Sultan Mosque (Üsküdar)", 41.0270, 29.0145, views: 30_000), // ~1,1 km
            candidate("Small Fountain", 41.0215, 29.0060, views: 40),              // ~200 m, az bilinen
            candidate("Hagia Sophia", 41.0086, 28.9802, views: 400_000),           // ~2,4 km: çok uzak
        ]
        let ranked = Recommender.rank(candidates, anchors: [maidensTower], saved: [maidensTower])
        XCTAssertFalse(ranked.contains { $0.place.title == "Hagia Sophia" })
        XCTAssertEqual(ranked.first?.place.title, "Mihrimah Sultan Mosque (Üsküdar)")
        XCTAssertEqual(ranked.last?.place.title, "Small Fountain")
        XCTAssertEqual(ranked.first?.anchorName, "Kız Kulesi")
        XCTAssertGreaterThan(ranked.first?.walkingMinutes ?? 0, 10)
    }

    func testExcludedAndDuplicatesAreRemoved() {
        let candidates = [
            candidate("Maiden's Tower", 41.02111, 29.00417, views: 50_000, local: "Kız Kulesi"),
            candidate("Şemsi Pasha Mosque", 41.0262, 29.0101, views: 3000),
            candidate("Şemsi Pasha Mosque", 41.0262, 29.0101, views: 3100),
        ]
        let ranked = Recommender.rank(candidates, anchors: [maidensTower], saved: []) { $0.title == "Maiden's Tower" }
        XCTAssertEqual(ranked.map(\.place.title), ["Şemsi Pasha Mosque"])
        XCTAssertEqual(ranked.first?.place.monthlyViews, 3100)
    }

    func testNoAnchorsNoSuggestions() {
        XCTAssertTrue(Recommender.rank([candidate("A", 41, 29, views: 10)], anchors: [], saved: []).isEmpty)
    }

    func testAddedItemKeepsItsPlaceWhenListRefreshes() {
        let a = candidate("A", 41.022, 29.005, views: 100)
        let b = candidate("B", 41.023, 29.005, views: 100)
        let c = candidate("C", 41.024, 29.005, views: 100)
        func suggestion(_ place: WikipediaService.PopularPlace, _ score: Double) -> Recommender.Suggestion {
            Recommender.Suggestion(place: place, category: .sight, anchorName: "Kız Kulesi", distance: 100, score: score)
        }
        let previous = [suggestion(a, 3), suggestion(b, 2), suggestion(c, 1)]
        // B eklendi; yeni sıralamada B en üste çıkmış olsa da ikinci sırada kalır.
        let fresh = [suggestion(b, 9), suggestion(c, 5), suggestion(a, 4)]
        let merged = Recommender.merge(fresh, previous: previous, keeping: ["B"])
        XCTAssertEqual(merged.map(\.id), ["C", "B", "A"])
    }

    func testFoodIsSuggestedOnlyWhenDayHasNone() {
        XCTAssertTrue(Recommender.needsFood([maidensTower]))
        var cafe = maidensTower
        cafe.category = .cafe
        XCTAssertFalse(Recommender.needsFood([maidensTower, cafe]))
        XCTAssertFalse(Recommender.needsFood([]))
    }
}

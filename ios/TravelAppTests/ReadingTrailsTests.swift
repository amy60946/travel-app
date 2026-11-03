import CoreLocation
import XCTest
@testable import TravelApp

/// Wikipedia okuma izleri ("Buna bakanlar şunlara da baktı"): kare dosyası
/// betikteki biçimle okunur, kare adı betikle aynı hesaplanır, birlikte
/// okunan yer öneride öne geçer.
final class ReadingTrailsTests: XCTestCase {
    /// ios/scripts/reading_trails.py'nin yazdığı biçim (deneme verisiyle üretildi).
    private let tileJSON = """
    {"month":"2026-09","titles":["Maiden's Tower","Hagia Sophia","Galata Tower"],\
    "lat":[41.0211,41.0085,41.0256],"lon":[29.0041,28.9802,28.9741],"readers":[6250,20280,150],\
    "related":{"0":[[1,500],[2,150]]}}
    """

    func testTileGivesRelatedPlacesInOrder() throws {
        let tile = try JSONDecoder().decode(ReadingTrails.Tile.self, from: Data(tileJSON.utf8))
        let related = try XCTUnwrap(tile.items(for: "Maiden's Tower"))
        XCTAssertEqual(related.map(\.title), ["Hagia Sophia", "Galata Tower"])
        XCTAssertEqual(related[0].together, 500)
        XCTAssertEqual(related[0].readers, 6250)
        XCTAssertEqual(related[1].latitude, 41.0256, accuracy: 0.00001)
        XCTAssertNil(tile.items(for: "Hagia Sophia"), "Karede yalnızca kaynak yerlerin listesi var")
        XCTAssertNil(tile.items(for: "Topkapı Palace"))
    }

    func testTileNamesMatchTheScript() {
        // Python: f"{math.floor(lat / 0.5) * 0.5:.1f}_{math.floor(lon / 0.5) * 0.5:.1f}"
        XCTAssertEqual(ReadingTrails.tileName(latitude: 41.0211, longitude: 29.0041), "41.0_29.0")
        XCTAssertEqual(ReadingTrails.tileName(latitude: 35.7148, longitude: 139.7967), "35.5_139.5")
        XCTAssertEqual(ReadingTrails.tileName(latitude: -33.92, longitude: 18.42), "-34.0_18.0")
        XCTAssertEqual(ReadingTrails.tileName(latitude: 0.2, longitude: -0.2), "0.0_-0.5")
        XCTAssertEqual(ReadingTrails.tileName(latitude: -0.0, longitude: 0.0), "0.0_0.0")
    }

    func testPlaceNearTileEdgeAlsoChecksNeighbour() {
        // Galata Kulesi karenin içinde: tek kare.
        XCTAssertEqual(ReadingTrails.tileNames(latitude: 41.0256, longitude: 28.9741), ["41.0_28.5"])
        // Kız Kulesi 29,0 boylamına 400 m: yan kare de bakılır, önce kendi karesi.
        let names = ReadingTrails.tileNames(latitude: 41.0211, longitude: 29.0041)
        XCTAssertEqual(names.first, "41.0_29.0")
        XCTAssertTrue(names.contains("41.0_28.5"))
    }

    func testStrengthGrowsWithShareOfReaders() {
        typealias Related = ReadingTrails.Related
        XCTAssertEqual(Related.strength(together: 0, readers: 1000), 0)
        XCTAssertEqual(Related.strength(together: 10, readers: 0), 0)
        XCTAssertEqual(Related.strength(together: 50, readers: 10_000), 0.5, accuracy: 0.001)   // %0,5
        XCTAssertEqual(Related.strength(together: 150, readers: 10_000), 0.75, accuracy: 0.001) // %1,5
        XCTAssertLessThan(Related.strength(together: 5000, readers: 10_000), 1)
    }

    func testAlsoReadPlaceMovesUpInSuggestions() {
        let maidensTower = Place(name: "Kız Kulesi", city: "İstanbul", latitude: 41.02111, longitude: 29.00417,
                                 category: .viewpoint, source: .search, wikipediaTitle: "Maiden's Tower")
        func candidate(_ title: String, _ longitude: Double) -> WikipediaService.PopularPlace {
            WikipediaService.PopularPlace(title: title, latitude: 41.0262, longitude: longitude, monthlyViews: 3000,
                                          thumbnailURL: URL(string: "https://upload.wikimedia.org/x.jpg"))
        }
        // Aynı bilinirlik; A biraz daha yakın ama B'ye Kız Kulesi okurları da bakıyor.
        let candidates = [candidate("A Mosque", 29.0090), candidate("B Mosque", 29.0101)]
        let plain = Recommender.rank(candidates, anchors: [maidensTower], saved: [])
        XCTAssertEqual(plain.first?.place.title, "A Mosque")
        let boosted = Recommender.rank(candidates, anchors: [maidensTower], saved: [], alsoRead: ["B Mosque": 0.8])
        XCTAssertEqual(boosted.first?.place.title, "B Mosque")
        XCTAssertEqual(boosted.first?.alsoRead ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(boosted.last?.alsoRead, 0)
    }
}

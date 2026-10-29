import MapKit
import XCTest
@testable import TravelApp

/// Haritadaki pinlerin türü: addan tahmin ve Apple Haritalar türü.
final class PlaceCategoryTests: XCTestCase {
    func testGuessesFromName() {
        let cases: [(String, PlaceCategory)] = [
            ("Sensō-ji", .temple),
            ("Meiji Jingu", .temple),
            ("Süleymaniye Camii", .temple),
            ("浅草寺", .temple),
            ("Tokyo National Museum", .museum),
            ("İstanbul Modern Müzesi", .museum),
            ("teamLab Planets", .museum),
            ("Blue Bottle Coffee", .cafe),
            ("Fuglen Tokyo Cafe", .cafe),
            ("AFURI Ramen", .food),
            ("Sushi Dai", .food),
            ("Temple Bar", .bar),
            ("Park Hotel Tokyo", .hotel),
            ("Ueno Parkı", .park),
            ("Shinjuku Gyoen", .park),
            ("Tokyo Skytree", .viewpoint),
            ("Galata Kulesi", .viewpoint),
            ("Grand Bazaar", .shopping),
            ("Mısır Çarşısı", .shopping),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(PlaceCategory.guess(name: name), expected, name)
        }
    }

    func testUnknownNameIsNil() {
        XCTAssertNil(PlaceCategory.guess(name: "Shibuya Crossing"))
        // "park" kelimesinin başı olan "parking" park sayılmaz.
        XCTAssertNil(PlaceCategory.guess(name: "Times Parking"))
        // Kelime içinde geçen "bar" (Barcelona) bar sayılmaz.
        XCTAssertNil(PlaceCategory.guess(name: "Barcelona"))
    }

    func testAppleCategoryWinsWhenSpecific() {
        XCTAssertEqual(PlaceCategory(apple: .cafe, name: "Temple Cafe"), .cafe)
        XCTAssertEqual(PlaceCategory(apple: .museum, name: "Edo-Tokyo"), .museum)
        XCTAssertEqual(PlaceCategory(apple: .nightlife, name: "Golden Gai"), .bar)
    }

    func testNameWinsOverParkOrUnknown() {
        // Tapınak bahçesi Apple'da park olabilir; adı tapınak der.
        XCTAssertEqual(PlaceCategory(apple: .park, name: "Meiji Jingu"), .temple)
        XCTAssertEqual(PlaceCategory(apple: nil, name: "Gōtoku-ji"), .temple)
        XCTAssertEqual(PlaceCategory(apple: .park, name: "Yoyogi"), .park)
        XCTAssertEqual(PlaceCategory(apple: nil, name: "Shibuya Crossing"), .sight)
        XCTAssertEqual(PlaceCategory(apple: .publicTransport, name: "Shibuya Station"), .other)
    }

    @MainActor
    func testSavedPlaceMatchesNameNearby() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let store = AppStore(fileURL: url)
        let place = try XCTUnwrap(store.places.first { $0.name == "Sensō-ji" })
        XCTAssertNotNil(store.savedPlace(named: "sensō-ji", near: place.coordinate))
        let far = CLLocationCoordinate2D(latitude: place.latitude + 0.05, longitude: place.longitude)
        XCTAssertNil(store.savedPlace(named: "Sensō-ji", near: far))
    }
}

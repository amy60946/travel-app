import CoreLocation
import XCTest
@testable import TravelApp

/// Google Haritalar: yol çizgisinin açılması, yer türünün bizim türe
/// çevrilmesi ve dönüş simgeleri.
@MainActor
final class GoogleTests: XCTestCase {
    func testDecodesPolyline() {
        // Google'ın belgelerindeki örnek.
        let points = GoogleAPI.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 0.00001)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 0.00001)
        XCTAssertEqual(points[1].latitude, 40.7, accuracy: 0.00001)
        XCTAssertEqual(points[1].longitude, -120.95, accuracy: 0.00001)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 0.00001)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 0.00001)
        XCTAssertTrue(GoogleAPI.decodePolyline("").isEmpty)
    }

    func testMapsGoogleTypes() {
        let cases: [([String], String?, String, PlaceCategory)] = [
            (["ramen_restaurant", "restaurant", "food"], "ramen_restaurant", "Ichiran", .food),
            (["cafe", "food", "store"], "cafe", "Fuglen", .cafe),
            (["art_museum", "museum"], nil, "Mori Art Museum", .museum),
            (["buddhist_temple", "place_of_worship"], "buddhist_temple", "Sensō-ji", .temple),
            (["observation_deck", "tourist_attraction"], "observation_deck", "Shibuya Sky", .viewpoint),
            (["hotel", "lodging"], "hotel", "Park Hyatt Tokyo", .hotel),
            (["bar", "night_club"], "bar", "Golden Gai", .bar),
            (["clothing_store", "store"], "clothing_store", "Beams", .shopping),
            // Google "park" dese de adı tapınak: tapınak.
            (["park", "tourist_attraction"], "park", "Meiji Jingu", .temple),
            (["tourist_attraction"], "tourist_attraction", "Shibuya Crossing", .sight),
            (["point_of_interest"], nil, "Bilinmeyen Yer", .sight),
        ]
        for (types, primary, name, expected) in cases {
            XCTAssertEqual(PlaceCategory(googleTypes: types, primary: primary, name: name), expected, name)
        }
    }

    func testSymbolFromManeuver() {
        XCTAssertEqual(GuidanceView.symbol(maneuver: "TURN_LEFT", instruction: ""), "arrow.turn.up.left")
        XCTAssertEqual(GuidanceView.symbol(maneuver: "TURN_SLIGHT_RIGHT", instruction: ""), "arrow.up.right")
        XCTAssertEqual(GuidanceView.symbol(maneuver: "UTURN_RIGHT", instruction: ""), "arrow.uturn.down")
        XCTAssertEqual(GuidanceView.symbol(maneuver: "STRAIGHT", instruction: "Sola dönün"), "arrow.up")
        // Tür yoksa talimattaki kelimelerden.
        XCTAssertEqual(GuidanceView.symbol(maneuver: nil, instruction: "Sağa dönün"), "arrow.turn.up.right")
    }

    func testFittingFocus() {
        XCTAssertNil(MapFocus.fitting([]))
        let focus = MapFocus.fitting([
            CLLocationCoordinate2D(latitude: 35.66, longitude: 139.70),
            CLLocationCoordinate2D(latitude: 35.71, longitude: 139.80),
        ])
        guard case .region(let region)? = focus?.target else { return XCTFail("bölge bekleniyordu") }
        XCTAssertEqual(region.center.latitude, 35.685, accuracy: 0.001)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0.1)
        // Her odak yenidir: aynı yere ikinci kez gitmek de uygulanır.
        XCTAssertNotEqual(MapFocus.point(region.center, zoom: 12), MapFocus.point(region.center, zoom: 12))
    }
}

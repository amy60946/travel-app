import MapKit
import XCTest
@testable import TravelApp

/// Uygulama içi yol tarifi: dönüş simgesi ve rotadan uzaklık.
@MainActor
final class GuidanceTests: XCTestCase {
    func testSymbolFromInstruction() {
        let cases: [(String, String)] = [
            ("Turn left onto Kaminarimon-dori", "arrow.turn.up.left"),
            ("Turn right", "arrow.turn.up.right"),
            ("Sola dönün", "arrow.turn.up.left"),
            ("Sağa dönün", "arrow.turn.up.right"),
            ("Keep left", "arrow.up.left"),
            ("Hafif sağa dönün", "arrow.up.right"),
            ("The destination is on your left", "mappin.circle.fill"),
            ("Continue on Asakusa-dori", "arrow.up"),
        ]
        for (instruction, symbol) in cases {
            XCTAssertEqual(GuidanceView.symbol(for: instruction), symbol, instruction)
        }
    }

    func testDistanceToRoute() {
        // Doğu-batı yönünde ~900 m'lik düz yol (Asakusa).
        var coordinates = [
            CLLocationCoordinate2D(latitude: 35.7100, longitude: 139.7900),
            CLLocationCoordinate2D(latitude: 35.7100, longitude: 139.8000),
        ]
        let line = MKPolyline(coordinates: &coordinates, count: coordinates.count)

        let onRoute = CLLocation(latitude: 35.7100, longitude: 139.7950)
        XCTAssertLessThan(WalkingGuide.distance(from: onRoute, to: line), 1)

        // ~111 m kuzeyde.
        let off = CLLocation(latitude: 35.7110, longitude: 139.7950)
        XCTAssertEqual(WalkingGuide.distance(from: off, to: line), 111, accuracy: 5)

        // Yolun bittiği yerin ötesinde: en yakın uç noktaya uzaklık.
        let past = CLLocation(latitude: 35.7100, longitude: 139.8010)
        XCTAssertEqual(WalkingGuide.distance(from: past, to: line), 90, accuracy: 10)
    }
}

import CoreLocation
import XCTest
@testable import TravelApp

/// "Gittim" (2026-11-05): yerin yanında birkaç dakika kalınca gidildi
/// sayılır; yanından yürüyüp geçmek, bir anlık sapan konum ya da belirsiz
/// konum sayılmaz.
final class VisitDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let cafe = VisitDetector.Target(id: UUID(), latitude: 35.7148, longitude: 139.7967, radius: 40)
    private let temple = VisitDetector.Target(id: UUID(), latitude: 35.7148, longitude: 139.7967, radius: 80)

    /// Yerin `meters` kuzeyinde (eksi: güneyinde), `seconds` saniye sonra.
    private func sample(_ target: VisitDetector.Target, meters: Double, after seconds: TimeInterval,
                        accuracy: CLLocationAccuracy = 10) -> (CLLocation, Date) {
        let latitude = target.latitude + meters / 111_320
        let time = start.addingTimeInterval(seconds)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: target.longitude),
                                  altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: time)
        return (location, time)
    }

    private func feed(_ detector: inout VisitDetector, _ target: VisitDetector.Target,
                      _ samples: [(meters: Double, seconds: TimeInterval)]) -> [TimeInterval] {
        var marked: [TimeInterval] = []
        for item in samples {
            let (location, time) = sample(target, meters: item.meters, after: item.seconds)
            if detector.update(location, targets: [target], now: time).contains(target.id) {
                marked.append(item.seconds)
            }
        }
        return marked
    }

    func testRadiusFollowsPlaceSize() {
        XCTAssertEqual(VisitDetector.radius(for: .cafe), 40)
        XCTAssertEqual(VisitDetector.radius(for: .temple), 80)
        XCTAssertGreaterThan(VisitDetector.radius(for: .park), VisitDetector.radius(for: .museum))
    }

    func testStayingThreeMinutesMarksOnce() {
        var detector = VisitDetector()
        let samples = stride(from: 0.0, through: 240, by: 15).map { (meters: 15.0, seconds: $0) }
        XCTAssertEqual(feed(&detector, cafe, samples), [180])
    }

    func testWalkingPastDoesNotMark() {
        // Tapınağın tam ortasından 1,4 m/sn yürüyerek geçmek (çember + pay 210 m ≈ 150 sn).
        var detector = VisitDetector()
        let samples = stride(from: 0.0, through: 400, by: 5).map { (meters: -250 + 1.4 * $0, seconds: $0) }
        XCTAssertEqual(feed(&detector, temple, samples), [])
    }

    func testOneStrayLocationKeepsTheCount() {
        var detector = VisitDetector()
        let marked = feed(&detector, cafe, [(10, 0), (20, 60), (120, 90), (15, 110), (10, 150), (12, 185)])
        XCTAssertEqual(marked, [185])
    }

    func testStrayLocationIsNotAVisit() {
        // Süre dolduğu anda uzaktaysa işaretlenmez; geri gelince işaretlenir.
        var detector = VisitDetector()
        XCTAssertEqual(feed(&detector, cafe, [(10, 0), (150, 185), (10, 200)]), [200])
    }

    func testLeavingResetsTheCount() {
        var detector = VisitDetector()
        let marked = feed(&detector, cafe, [(10, 0), (300, 30), (300, 90), (10, 100), (10, 185), (10, 285)])
        XCTAssertEqual(marked, [285], "90. saniyede 45 sn'den uzun uzaktaydı; sayaç 100'de yeniden başladı")
    }

    func testInaccurateLocationIsIgnored() {
        var detector = VisitDetector()
        for seconds in stride(from: 0.0, through: 300, by: 30) {
            let (location, time) = sample(cafe, meters: 0, after: seconds, accuracy: 150)
            XCTAssertEqual(detector.update(location, targets: [cafe], now: time), [])
        }
    }

    func testLongGapStartsOver() {
        // Uygulama 400 sn arkadaydı: önceki yakınlık sayılmaz.
        var detector = VisitDetector()
        XCTAssertEqual(feed(&detector, cafe, [(10, 0), (10, 400), (10, 500), (10, 585)]), [585])
    }

    func testRegionStayNeedsFiveMinutes() {
        XCTAssertFalse(VisitDetector.regionVisit(enteredAt: nil, exitedAt: start))
        XCTAssertFalse(VisitDetector.regionVisit(enteredAt: start, exitedAt: start.addingTimeInterval(4 * 60)))
        XCTAssertTrue(VisitDetector.regionVisit(enteredAt: start, exitedAt: start.addingTimeInterval(6 * 60)))
        XCTAssertFalse(VisitDetector.regionVisit(enteredAt: start, exitedAt: start.addingTimeInterval(13 * 3600)),
                       "Çıkış olayı kaçmış")
    }

    func testVisitMatchesTheNearestPlace() {
        let near = VisitDetector.Target(id: UUID(), latitude: 35.71480, longitude: 139.7967, radius: 40)
        let next = VisitDetector.Target(id: UUID(), latitude: 35.71520, longitude: 139.7967, radius: 40)
        let spot = CLLocationCoordinate2D(latitude: 35.71490, longitude: 139.7967)
        XCTAssertEqual(VisitDetector.match(visit: spot, accuracy: 30, targets: [next, near]), near.id)
        XCTAssertNil(VisitDetector.match(visit: spot, accuracy: 500, targets: [near]), "Konum çok belirsiz")
        let far = CLLocationCoordinate2D(latitude: 35.7200, longitude: 139.7967)
        XCTAssertNil(VisitDetector.match(visit: far, accuracy: 30, targets: [near, next]))
    }

    func testRegionsAreTheNearestTwenty() {
        let here = CLLocation(latitude: 35.7148, longitude: 139.7967)
        let targets = (0..<30).map { index in
            VisitDetector.Target(id: UUID(), latitude: 35.7148 + Double(index) * 0.001, longitude: 139.7967, radius: 40)
        }
        let osaka = VisitDetector.Target(id: UUID(), latitude: 34.6937, longitude: 135.5023, radius: 40)
        let chosen = VisitDetector.nearest(targets.reversed() + [osaka], to: here)
        XCTAssertEqual(chosen.count, 20)
        XCTAssertEqual(chosen.first?.id, targets[0].id)
        XCTAssertFalse(chosen.contains(osaka))
        XCTAssertEqual(VisitDetector.nearest([osaka], to: here), [], "Başka şehir izlenmez")
    }

    func testPlaceTargetUsesCategoryRadius() {
        let place = Place(name: "Blue Bottle", city: "Tokyo", latitude: 35.7, longitude: 139.7,
                          category: .cafe, source: .search)
        let target = VisitDetector.target(for: place)
        XCTAssertEqual(target.id, place.id)
        XCTAssertEqual(target.radius, 40)
    }
}

import CoreLocation
import XCTest
@testable import TravelApp

/// "Gittim" (2026-11-05, benzer uygulamalara göre): 70 m içinde 140 sn
/// durunca en yakın yer (Radar, Foursquare); büyük yerde 5 dakika gezinme;
/// yerin anlatımını yanındayken 1 dakika dinleme. Yanından yürüyüp geçmek,
/// bir anlık sapan konum ya da belirsiz konum sayılmaz.
final class VisitDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let base = CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967)
    private lazy var cafe = VisitDetector.Target(id: UUID(), latitude: base.latitude, longitude: base.longitude,
                                                 radius: 50, name: "Blue Bottle")
    private lazy var temple = VisitDetector.Target(id: UUID(), latitude: base.latitude, longitude: base.longitude,
                                                   radius: 100, name: "Sensō-ji")

    /// Yerin `north` m kuzeyinde, `east` m doğusunda, `seconds` saniye sonra.
    private func sample(north: Double, east: Double = 0, after seconds: TimeInterval,
                        accuracy: CLLocationAccuracy = 10) -> CLLocation {
        let latitude = base.latitude + north / 111_320
        let longitude = base.longitude + east / (111_320 * cos(base.latitude * .pi / 180))
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                          altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10,
                          timestamp: start.addingTimeInterval(seconds))
    }

    /// Konumları sırayla verir; her yerin işaretlendiği saniyeler.
    private func feed(_ targets: [VisitDetector.Target], _ samples: [(north: Double, east: Double, seconds: TimeInterval)],
                      narrating: String? = nil) -> [UUID: [TimeInterval]] {
        var detector = VisitDetector()
        var marked: [UUID: [TimeInterval]] = [:]
        for item in samples {
            let location = sample(north: item.north, east: item.east, after: item.seconds)
            for id in detector.update(location, targets: targets, now: location.timestamp, narrating: narrating) {
                marked[id, default: []].append(item.seconds)
            }
        }
        return marked
    }

    private func feed(_ target: VisitDetector.Target, _ samples: [(north: Double, seconds: TimeInterval)],
                      narrating: String? = nil) -> [TimeInterval] {
        feed([target], samples.map { (north: $0.north, east: 0, seconds: $0.seconds) }, narrating: narrating)[target.id] ?? []
    }

    /// `from` m'den saniyede `speed` m ile kuzeye yürüyüş, 5 sn'de bir konum.
    private func walk(from: Double, speed: Double, until seconds: TimeInterval) -> [(north: Double, seconds: TimeInterval)] {
        stride(from: 0.0, through: seconds, by: 5).map { (north: from + speed * $0, seconds: $0) }
    }

    func testRadiusFollowsPlaceSize() {
        XCTAssertEqual(VisitDetector.radius(for: .cafe), 50)
        XCTAssertEqual(VisitDetector.radius(for: .temple), 100)
        XCTAssertEqual(VisitDetector.radius(for: .park), 200)
    }

    func testStoppingMarksOnce() {
        // 15 sn'de bir, kafenin 15 m yanında: 140. saniyeden sonraki ilk konumda.
        let samples = stride(from: 0.0, through: 400, by: 15).map { (north: 15.0, seconds: $0) }
        XCTAssertEqual(feed(cafe, samples), [150])
    }

    func testWalkingPastDoesNotMark() {
        // Tapınağın tam ortasından geçmek (normal ve yavaş yürüyüş).
        XCTAssertEqual(feed(temple, walk(from: -250, speed: 1.4, until: 400)), [])
        XCTAssertEqual(feed(temple, walk(from: -250, speed: 1.0, until: 500)), [])
        XCTAssertEqual(feed(cafe, walk(from: -150, speed: 1.0, until: 300)), [])
    }

    func testStopSnapsToTheNearestOfTwoCafes() {
        let next = VisitDetector.Target(id: UUID(), latitude: base.latitude + 40 / 111_320, longitude: base.longitude,
                                        radius: 50, name: "Onibus Coffee")
        let samples = stride(from: 0.0, through: 400, by: 20).map { (north: 10.0, east: 0.0, seconds: $0) }
        let marked = feed([next, cafe], samples)
        XCTAssertEqual(marked[cafe.id], [140])
        XCTAssertNil(marked[next.id], "Yan kafe 30 m uzakta; yalnızca en yakını")
    }

    func testOneStrayLocationKeepsTheCount() {
        XCTAssertEqual(feed(cafe, [(10, 0), (20, 60), (120, 90), (15, 110), (10, 150)]), [150])
    }

    func testStrayLocationIsNotAVisit() {
        // Süre dolduğu anda uzaktaysa işaretlenmez; geri gelince işaretlenir.
        XCTAssertEqual(feed(cafe, [(10, 0), (150, 185), (10, 200)]), [200])
    }

    func testLeavingStartsANewStop() {
        let marked = feed(cafe, [(10, 0), (300, 30), (300, 90), (10, 100), (10, 150), (10, 200), (10, 250)])
        XCTAssertEqual(marked, [250], "Uzaklaşıp 100. saniyede döndü; yeni durma oradan sayılır")
    }

    func testWanderingInAParkMarksAfterFiveMinutes() {
        // Parkın ortasından 120 m uzakta, durmadan dolaşmak (saniyede 0,8 m).
        let park = VisitDetector.Target(id: UUID(), latitude: base.latitude, longitude: base.longitude,
                                        radius: 200, name: "Ueno Park")
        let samples = stride(from: 0.0, through: 420, by: 10).map { seconds in
            let angle = 0.8 * seconds / 120
            return (north: 120 * cos(angle), east: 120 * sin(angle), seconds: seconds)
        }
        XCTAssertEqual(feed([park], samples)[park.id], [300])
    }

    func testListeningNearbyMarks() {
        // Yavaş yürüyerek geçerken tapınağın anlatımını dinlemek: 150 m'ye girince 1 dakika.
        XCTAssertEqual(feed(temple, walk(from: -250, speed: 1.0, until: 500), narrating: "Sensō-ji"), [155])
        XCTAssertEqual(feed(temple, walk(from: -250, speed: 1.0, until: 500), narrating: "sensō-JI").count, 1)
    }

    func testListeningAwayOrToAnotherPlaceDoesNotMark() {
        // Evde dinlemek (2 km uzakta) sayılmaz.
        let home = stride(from: 0.0, through: 600, by: 10).map { (north: 2_000.0, seconds: $0) }
        XCTAssertEqual(feed(temple, home, narrating: "Sensō-ji"), [])
        // Kafenin yanında başka yerin anlatımı.
        let nearCafe = stride(from: 0.0, through: 120, by: 5).map { (north: 20.0, seconds: $0) }
        XCTAssertEqual(feed(cafe, nearCafe, narrating: "Sensō-ji"), [])
    }

    func testInaccurateLocationIsIgnored() {
        var detector = VisitDetector()
        for seconds in stride(from: 0.0, through: 400, by: 20) {
            let location = sample(north: 0, after: seconds, accuracy: 150)
            XCTAssertEqual(detector.update(location, targets: [cafe], now: location.timestamp), [])
        }
    }

    func testLongGapStartsOver() {
        // Uygulama 400 sn arkadaydı: önceki durma sayılmaz.
        XCTAssertEqual(feed(cafe, [(10, 0), (10, 400), (10, 500), (10, 585)]), [585])
    }

    func testRegionStayNeedsFiveMinutes() {
        XCTAssertFalse(VisitDetector.regionVisit(enteredAt: nil, exitedAt: start))
        XCTAssertFalse(VisitDetector.regionVisit(enteredAt: start, exitedAt: start.addingTimeInterval(4 * 60)))
        XCTAssertTrue(VisitDetector.regionVisit(enteredAt: start, exitedAt: start.addingTimeInterval(6 * 60)))
        XCTAssertFalse(VisitDetector.regionVisit(enteredAt: start, exitedAt: start.addingTimeInterval(13 * 3600)),
                       "Çıkış olayı kaçmış")
    }

    func testVisitMatchesTheNearestPlace() {
        let near = VisitDetector.Target(id: UUID(), latitude: 35.71480, longitude: 139.7967, radius: 50)
        let next = VisitDetector.Target(id: UUID(), latitude: 35.71520, longitude: 139.7967, radius: 50)
        let spot = CLLocationCoordinate2D(latitude: 35.71490, longitude: 139.7967)
        XCTAssertEqual(VisitDetector.match(visit: spot, accuracy: 30, targets: [next, near]), near.id)
        XCTAssertNil(VisitDetector.match(visit: spot, accuracy: 500, targets: [near]), "Konum çok belirsiz")
        let far = CLLocationCoordinate2D(latitude: 35.7200, longitude: 139.7967)
        XCTAssertNil(VisitDetector.match(visit: far, accuracy: 30, targets: [near, next]))
    }

    func testRegionsAreTheNearestTwenty() {
        let here = CLLocation(latitude: 35.7148, longitude: 139.7967)
        let targets = (0..<30).map { index in
            VisitDetector.Target(id: UUID(), latitude: 35.7148 + Double(index) * 0.001, longitude: 139.7967, radius: 50)
        }
        let osaka = VisitDetector.Target(id: UUID(), latitude: 34.6937, longitude: 135.5023, radius: 50)
        let chosen = VisitDetector.nearest(targets.reversed() + [osaka], to: here)
        XCTAssertEqual(chosen.count, 20)
        XCTAssertEqual(chosen.first?.id, targets[0].id)
        XCTAssertFalse(chosen.contains(osaka))
        XCTAssertEqual(VisitDetector.nearest([osaka], to: here), [], "Başka şehir izlenmez")
    }

    func testPlaceTargetUsesCategoryRadiusAndName() {
        let place = Place(name: "Blue Bottle", city: "Tokyo", latitude: 35.7, longitude: 139.7,
                          category: .cafe, source: .search)
        let target = VisitDetector.target(for: place)
        XCTAssertEqual(target.id, place.id)
        XCTAssertEqual(target.radius, 50)
        XCTAssertEqual(target.name, "Blue Bottle")
    }
}

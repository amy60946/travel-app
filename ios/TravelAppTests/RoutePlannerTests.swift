import XCTest
@testable import TravelApp

final class RoutePlannerTests: XCTestCase {
    private func point(_ lat: Double, _ lon: Double) -> RoutePlanner.Point {
        RoutePlanner.Point(id: UUID(), latitude: lat, longitude: lon)
    }

    func testNearbyPlacesShareADay() {
        // İki ayrı küme: Asakusa çevresi ve Shibuya çevresi.
        let asakusa = [point(35.7148, 139.7967), point(35.7101, 139.8107), point(35.7156, 139.7745)]
        let shibuya = [point(35.6595, 139.7005), point(35.6715, 139.7031), point(35.6764, 139.6993)]
        let plan = RoutePlanner.plan(asakusa + shibuya, days: 2, maxPerDay: 6)

        XCTAssertEqual(plan.days.count, 2)
        XCTAssertTrue(plan.leftOver.isEmpty)
        let groups = plan.days.map(Set.init)
        XCTAssertTrue(groups.contains(Set(asakusa.map(\.id))))
        XCTAssertTrue(groups.contains(Set(shibuya.map(\.id))))
    }

    func testRespectsDailyLimitAndCapacity() {
        let points = (0..<10).map { point(35.68 + Double($0) * 0.001, 139.76) }
        let plan = RoutePlanner.plan(points, days: 2, maxPerDay: 4)

        XCTAssertEqual(plan.days.count, 2)
        XCTAssertTrue(plan.days.allSatisfy { $0.count <= 4 })
        XCTAssertEqual(plan.days.flatMap { $0 }.count, 8)
        // Sığmayanlar listenin sonundakiler.
        XCTAssertEqual(plan.leftOver, points.suffix(2).map(\.id))
    }

    func testEveryPlaceAppearsOnce() {
        let points = (0..<12).map { i in point(35.6 + Double(i % 4) * 0.03, 139.7 + Double(i / 4) * 0.03) }
        let plan = RoutePlanner.plan(points, days: 3, maxPerDay: 6)
        let all = plan.days.flatMap { $0 } + plan.leftOver
        XCTAssertEqual(Set(all), Set(points.map(\.id)))
        XCTAssertEqual(all.count, points.count)
    }

    func testMoreDaysThanPlaces() {
        let plan = RoutePlanner.plan([point(35.7, 139.7)], days: 3, maxPerDay: 5)
        XCTAssertEqual(plan.days.count, 3)
        XCTAssertEqual(plan.days.filter { !$0.isEmpty }.count, 1)
    }

    func testNearestNeighborDoesNotZigZag() {
        // Düz bir hat üzerinde karışık verilen noktalar sırayla dizilmeli.
        let line = (0..<5).map { point(35.68, 139.70 + Double($0) * 0.01) }
        let shuffled = [line[2], line[0], line[4], line[1], line[3]]
        let ordered = RoutePlanner.nearestNeighborOrder(shuffled).map(\.id)
        XCTAssertTrue(ordered == line.map(\.id) || ordered == line.reversed().map(\.id))
    }
}

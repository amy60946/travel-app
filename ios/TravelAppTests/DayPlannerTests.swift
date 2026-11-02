import XCTest
@testable import TravelApp

final class DayPlannerTests: XCTestCase {
    /// Birbirine yakın (birkaç yüz metre) yerler: sırayı saatler belirlesin.
    private func stop(_ category: PlaceCategory, _ offset: Double, pinned: Int? = nil,
                      minutes: Int? = nil) -> DayPlanner.Stop {
        DayPlanner.Stop(id: UUID(), latitude: 35.66 + offset, longitude: 139.70, category: category,
                        visitMinutes: minutes ?? category.averageMinutes, pinned: pinned)
    }

    func testScheduleWaitsForPinnedTime() {
        let museum = stop(.museum, 0)
        let dinner = stop(.food, 0.001, pinned: 19 * 60)
        let entries = DayPlanner.schedule([museum, dinner])
        XCTAssertEqual(entries.first?.arrival, DayPlanner.dayStart)
        XCTAssertEqual(entries.last?.arrival, 19 * 60, "sabit saatten önce varılırsa beklenir")
        XCTAssertEqual(entries.last?.reason, .pinned)
    }

    func testScheduleUsesGoogleWalkingTotal() {
        let a = stop(.sight, 0, minutes: 30)
        let b = stop(.sight, 0.01, minutes: 30)
        let entries = DayPlanner.schedule([a, b], walkingMinutes: 20)
        XCTAssertEqual(entries.last?.arrival, DayPlanner.dayStart + 30 + 20)
        XCTAssertEqual(DayPlanner.totalMinutes([a, b], walkingMinutes: 20), 30 + 20 + 30)
    }

    func testSmartOrderPutsMuseumFirstAndBarLast() throws {
        let bar = stop(.bar, 0)
        let shopping = stop(.shopping, 0.001)
        let museum = stop(.museum, 0.002)
        let lunch = stop(.food, 0.003)
        let temple = stop(.temple, 0.004)
        let best = try XCTUnwrap(DayPlanner.smartOrders([bar, shopping, museum, lunch, temple]).first)
        XCTAssertEqual(best.count, 5)
        XCTAssertTrue([museum.id, temple.id].contains(best.first?.id), "müze ya da tapınak sabah")
        XCTAssertEqual(best.last?.id, bar.id, "bar gün sonunda")
        let lunchIndex = try XCTUnwrap(best.firstIndex { $0.id == lunch.id })
        let shoppingIndex = try XCTUnwrap(best.firstIndex { $0.id == shopping.id })
        XCTAssertLessThan(lunchIndex, shoppingIndex, "öğle yemeği alışverişten önce")
    }

    func testSmartOrderReachesPinnedPlaceOnTime() throws {
        let museum = stop(.museum, 0)
        let park = stop(.park, 0.002)
        let dinner = stop(.food, 0.001, pinned: 19 * 60)
        let viewpoint = stop(.viewpoint, 0.003)
        let best = try XCTUnwrap(DayPlanner.smartOrders([dinner, museum, park, viewpoint]).first)
        let entries = DayPlanner.schedule(best)
        let arrival = try XCTUnwrap(entries.first { $0.id == dinner.id }?.arrival)
        XCTAssertEqual(arrival, 19 * 60)
        XCTAssertEqual(Set(best.map(\.id)).count, 4, "hiçbir yer dışarıda kalmaz")
    }

    func testSmartOrdersOffersAlternatives() {
        let stops = [stop(.museum, 0), stop(.food, 0.01), stop(.park, 0.02), stop(.cafe, 0.03), stop(.sight, 0.04)]
        let options = DayPlanner.smartOrders(stops)
        XCTAssertGreaterThan(options.count, 1)
        XCTAssertLessThanOrEqual(options.count, 3)
        XCTAssertEqual(Set(options.map { $0.map(\.id) }).count, options.count, "seçenekler birbirinden farklı")
    }

    func testClock() {
        XCTAssertEqual(DayPlanner.clock(9 * 60), "09:00")
        XCTAssertEqual(DayPlanner.clock(14 * 60 + 5), "14:05")
        XCTAssertEqual(DayPlanner.clock(24 * 60 + 30), "00:30")
    }

    func testNearestNeighborFromLocation() {
        let far = RoutePlanner.Point(id: UUID(), latitude: 35.70, longitude: 139.70)
        let near = RoutePlanner.Point(id: UUID(), latitude: 35.661, longitude: 139.70)
        let middle = RoutePlanner.Point(id: UUID(), latitude: 35.68, longitude: 139.70)
        let user = RoutePlanner.Point(id: UUID(), latitude: 35.66, longitude: 139.70)
        let order = RoutePlanner.nearestNeighborOrder([far, middle, near], from: user).map(\.id)
        XCTAssertEqual(order, [near.id, middle.id, far.id])
    }
}

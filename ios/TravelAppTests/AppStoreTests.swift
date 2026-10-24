import XCTest
@testable import TravelApp

@MainActor
final class AppStoreTests: XCTestCase {
    private func makeStore() -> AppStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        return AppStore(fileURL: url)
    }

    func testStartsWithSampleData() {
        let store = makeStore()
        XCTAssertFalse(store.places.isEmpty)
        XCTAssertEqual(store.cities.first?.name, "Tokyo")
        XCTAssertTrue(store.cities.first?.hasTrip ?? false)
    }

    func testRemoveAndUndo() throws {
        let store = makeStore()
        let place = try XCTUnwrap(store.places(in: "Tokyo").first)
        XCTAssertTrue(store.isPlanned(place))

        store.removeFromPlan(place)
        XCTAssertFalse(store.isPlanned(place))
        XCTAssertNotNil(store.undoMessage)

        store.undo()
        XCTAssertTrue(store.isPlanned(place))
        XCTAssertNil(store.undoMessage)
    }

    func testFewerDaysLeavesPlacesOut() {
        let store = makeStore()
        store.setPace(.relaxed, city: "Tokyo")
        store.setDays(1, city: "Tokyo")
        let plan = store.dayPlan(for: "Tokyo")
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertLessThanOrEqual(plan.days[0].count, Pace.relaxed.stopsPerDay.upperBound)
        XCTAssertFalse(plan.leftOver.isEmpty)
    }

    func testStatePersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let first = AppStore(fileURL: url)
        let place = Place(name: "Test", city: "Kyoto", latitude: 35.0, longitude: 135.7,
                          category: .temple, source: .manual)
        first.add(place, plan: true)

        let second = AppStore(fileURL: url)
        XCTAssertEqual(second.place(place.id)?.name, "Test")
        XCTAssertTrue(second.isPlanned(place))
    }
}

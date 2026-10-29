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

    func testSampleTripKeepsEveryPlaceInADay() {
        let store = makeStore()
        let planned = store.trip(for: "Tokyo").placeIDs.count
        let days = store.dayPlan(for: "Tokyo")
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days.reduce(0) { $0 + $1.count }, planned)
        XCTAssertTrue(days.allSatisfy { !$0.isEmpty }, "\(days.map(\.count))")

        // Tek günde de hiçbir yer dışarıda kalmaz.
        store.setDays(1, city: "Tokyo")
        XCTAssertEqual(store.dayPlan(for: "Tokyo").first?.count, planned)
    }

    func testMoveToAnotherDay() throws {
        let store = makeStore()
        let before = store.dayPlan(for: "Tokyo")
        let place = try XCTUnwrap(before[0].first)

        store.move(place, toDay: 2)
        let after = store.dayPlan(for: "Tokyo")
        XCTAssertEqual(store.dayIndex(of: place), 2)
        XCTAssertEqual(after.reduce(0) { $0 + $1.count }, before.reduce(0) { $0 + $1.count })
        // Diğer yerler günlerinde kalır.
        for (index, stops) in before.enumerated() {
            for stop in stops where stop.id != place.id {
                XCTAssertEqual(store.dayIndex(of: stop), index, stop.name)
            }
        }
        XCTAssertNotNil(store.undoMessage)

        store.undo()
        XCTAssertEqual(store.dayIndex(of: place), 0)
    }

    func testUserChoosesTheDay() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.dayPlan(for: "Tokyo")[0].first)
        store.move(first, toDay: 1)

        // Gün seçilmezse 1. güne; seçilirse o güne eklenir (en yakın güne değil).
        let near = try XCTUnwrap(store.dayPlan(for: "Tokyo")[2].first)
        let cafe = Place(name: "Yakın kafe", city: "Tokyo", latitude: near.latitude + 0.0004,
                         longitude: near.longitude, category: .cafe, source: .manual)
        store.add(cafe, plan: true)
        XCTAssertEqual(store.dayIndex(of: cafe), 0)
        let bar = Place(name: "Bar", city: "Tokyo", latitude: 35.66, longitude: 139.70, category: .bar, source: .manual)
        store.add(bar, plan: true, day: 2)
        XCTAssertEqual(store.dayIndex(of: bar), 2)
        store.removeFromPlan(cafe)
        store.addToPlan([cafe.id], city: "Tokyo", day: 1)
        XCTAssertEqual(store.dayIndex(of: cafe), 1)
        XCTAssertEqual(store.dayIndex(of: first), 1)

        // Son gün silinince yerleri yeni son güne geçer; geri eklenen gün boştur.
        let planned = store.trip(for: "Tokyo").placeIDs.count
        store.setDays(2, city: "Tokyo")
        XCTAssertNotNil(store.undoMessage)
        XCTAssertEqual(store.dayIndex(of: bar), 1)
        XCTAssertEqual(store.dayPlan(for: "Tokyo").reduce(0) { $0 + $1.count }, planned)
        store.setDays(3, city: "Tokyo")
        XCTAssertEqual(store.dayPlan(for: "Tokyo")[2].count, 0)
        XCTAssertEqual(store.dayIndex(of: first), 1)
    }

    func testMovedDayPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let first = AppStore(fileURL: url)
        let place = try XCTUnwrap(first.dayPlan(for: "Tokyo")[0].first)
        first.move(place, toDay: 1)

        let second = AppStore(fileURL: url)
        XCTAssertEqual(second.dayIndex(of: place), 1)
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

    func testImportedPlaceClearsPendingPost() throws {
        let store = makeStore()
        let url = try XCTUnwrap(URL(string: "https://www.instagram.com/p/ABC123/"))
        let post = SocialExport.Post(url: url, source: .instagram, author: "afuri_official")
        store.addPending([post])
        XCTAssertFalse(store.hasPlace(post))
        XCTAssertEqual(store.pendingPosts.count, 1)

        let place = Place(name: "AFURI Ebisu", city: "Tokyo", latitude: 35.6467, longitude: 139.7101,
                          category: .food, source: .instagram,
                          sourceURL: URL(string: "https://www.instagram.com/p/ABC123/?igsh=1"))
        XCTAssertEqual(store.importPlaces([place]), 1)
        XCTAssertTrue(store.pendingPosts.isEmpty)
        XCTAssertTrue(store.hasPlace(post))
    }
}

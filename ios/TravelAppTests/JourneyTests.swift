import XCTest
@testable import TravelApp

/// Çok şehirli gezi: şehirler sırayla, gün aralıkları, uçuş ve konaklama.
@MainActor
final class JourneyTests: XCTestCase {
    private func makeStore(url: URL? = nil) -> AppStore {
        AppStore(fileURL: url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json"))
    }

    private let ankara = CityChoice(name: "Ankara", countryCode: "TR", latitude: 39.93, longitude: 32.86)
    private let kapadokya = CityChoice(name: "Kapadokya", countryCode: "TR", latitude: 38.64, longitude: 34.83,
                                       englishTitle: "Cappadocia")

    func testDayRangesFollowEachOther() {
        let ranges = Journey.dayRanges(days: [3, 2, 1])
        XCTAssertEqual(ranges, [1...3, 4...5, 6...6])
        XCTAssertEqual(Journey.defaultName(for: ["A", "B", "C", "D", "E"]), "A, B, C +2")
    }

    func testOldCityPlanBecomesOneCityJourney() throws {
        let store = makeStore()
        let journey = try XCTUnwrap(store.journey(containing: "Tokyo"))
        XCTAssertEqual(journey.stops.map(\.city), ["Tokyo"])
        XCTAssertEqual(store.days(of: journey), [3])
    }

    func testCreateAndAddCities() throws {
        let store = makeStore()
        // "Istanbul" kayıtlı "İstanbul"un yanında: aynı şehir sayılır.
        let istanbul = CityChoice(name: "Istanbul", countryCode: "TR", latitude: 41.01, longitude: 28.98)
        let id = store.createJourney(cities: [istanbul, ankara, ankara])
        var journey = try XCTUnwrap(store.journey(id))
        XCTAssertEqual(journey.stops.map(\.city), ["İstanbul", "Ankara"])
        XCTAssertEqual(journey.name, "İstanbul, Ankara")
        XCTAssertEqual(store.journeys.first?.id, id)

        store.addStops([kapadokya], to: id, at: 1)
        journey = try XCTUnwrap(store.journey(id))
        XCTAssertEqual(journey.stops.map(\.city), ["İstanbul", "Kapadokya", "Ankara"])
        XCTAssertEqual(journey.stops[1].englishTitle, "Cappadocia")
        XCTAssertTrue(store.cities.contains { $0.name == "Ankara" && $0.placeCount == 0 })
        XCTAssertNotNil(store.center(of: "Ankara"))

        store.setDays(3, stop: journey.stops[0].id)
        let updated = try XCTUnwrap(store.journey(id))
        XCTAssertEqual(Journey.dayRanges(days: store.days(of: updated)), [1...3, 4...5, 6...7])

        store.moveStop(journey.stops[2].id, by: -1, in: id)
        XCTAssertEqual(store.journey(id)?.stops.map(\.city), ["İstanbul", "Ankara", "Kapadokya"])

        store.removeStop(journey.stops[0].id, from: id)
        XCTAssertEqual(store.journey(id)?.stops.map(\.city), ["Ankara", "Kapadokya"])
        store.undo()
        XCTAssertEqual(store.journey(id)?.stops.count, 3)
    }

    func testFlightAndStayPersist() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let store = makeStore(url: url)
        let id = store.createJourney(name: "Türkiye", cities: [ankara, kapadokya])
        let stops = try XCTUnwrap(store.journey(id)?.stops)
        store.setFlight(Flight(from: "Ankara", number: "TK 2006", departure: "09:40"), stop: stops[1].id, in: id)
        store.addStay(Stay(name: "Otel", latitude: nil, longitude: nil, nights: 2), stop: stops[0].id, in: id)

        let reopened = makeStore(url: url)
        let journey = try XCTUnwrap(reopened.journey(id))
        XCTAssertEqual(journey.name, "Türkiye")
        XCTAssertEqual(journey.stops[1].flight?.summary, "TK 2006 · 09:40")
        XCTAssertEqual(journey.stops[0].stays.first?.nights, 2)
        // Silinen gezi yeniden açılışta geri gelmez.
        reopened.deleteJourney(id)
        XCTAssertNil(makeStore(url: url).journey(id))
    }

    func testCountryFlagsAndSearch() {
        XCTAssertEqual(Country.flag("TR"), "🇹🇷")
        XCTAssertEqual(Continent.all.count, 6)
        XCTAssertEqual(Set(Country.all.map(\.code)).count, Country.all.count)
        XCTAssertTrue(Country.matching("japa").contains { $0.code == "JP" })
        XCTAssertTrue(Country.matching("korea").contains { $0.code == "KR" })
        XCTAssertEqual(Continent.of("MA")?.id, "africa")
    }
}

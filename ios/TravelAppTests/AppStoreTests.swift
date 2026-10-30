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

    /// Örnek Tokyo gezisinin şehri.
    private func tokyo(_ store: AppStore) throws -> UUID {
        try XCTUnwrap(store.stops(in: "Tokyo").first?.id)
    }

    func testRemoveAndUndo() throws {
        let store = makeStore()
        let stop = try tokyo(store)
        let place = try XCTUnwrap(store.places(in: "Tokyo").first)
        XCTAssertTrue(store.isPlanned(place))

        store.removeFromPlan(place, stop: stop)
        XCTAssertFalse(store.isPlanned(place))
        XCTAssertNotNil(store.undoMessage)

        store.undo()
        XCTAssertTrue(store.isPlanned(place))
        XCTAssertNil(store.undoMessage)
    }

    /// Koleksiyondaki kayıtlı yer bir gezinin gününe de eklenebilir
    /// (BOHO CO. COFFEE: "Bulgurlu" koleksiyonunda, İstanbul gezisinin 3. günü).
    func testCollectedPlaceCanBePlannedInATrip() throws {
        let store = makeStore()
        let stop = try tokyo(store)
        store.setDays(3, stop: stop)
        let cafe = Place(name: "BOHO CO. COFFEE", city: "Shibuya", latitude: 35.66, longitude: 139.70,
                         category: .cafe, source: .search)
        store.add(cafe)
        let collection = store.createCollection(name: "Bulgurlu", emoji: "☕️", color: 0)
        store.toggle(.place(cafe), in: collection)
        XCTAssertFalse(store.isPlanned(cafe, stop: stop))

        store.plan(cafe, stop: stop, day: 2)
        let planned = try XCTUnwrap(store.place(cafe.id))
        XCTAssertTrue(store.isPlanned(planned, stop: stop))
        XCTAssertEqual(planned.city, "Tokyo")
        XCTAssertEqual(store.dayIndex(of: planned, stop: stop), 2)
        XCTAssertTrue(store.contains(.place(planned), in: collection), "koleksiyonda da kalır")

        // Tek "Geri al" ikisini birden geri alır.
        store.undo()
        XCTAssertEqual(store.place(cafe.id)?.city, "Shibuya")
        XCTAssertFalse(store.isPlanned(cafe, stop: stop))
    }

    func testSampleTripKeepsEveryPlaceInADay() throws {
        let store = makeStore()
        let stop = try tokyo(store)
        let planned = store.trip(stop: stop).placeIDs.count
        let days = store.dayPlan(stop: stop)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days.reduce(0) { $0 + $1.count }, planned)
        XCTAssertTrue(days.allSatisfy { !$0.isEmpty }, "\(days.map(\.count))")

        // Tek günde de hiçbir yer dışarıda kalmaz.
        store.setDays(1, stop: stop)
        XCTAssertEqual(store.dayPlan(stop: stop).first?.count, planned)
    }

    func testMoveToAnotherDay() throws {
        let store = makeStore()
        let stop = try tokyo(store)
        let before = store.dayPlan(stop: stop)
        let place = try XCTUnwrap(before[0].first)

        store.move(place, toDay: 2, stop: stop)
        let after = store.dayPlan(stop: stop)
        XCTAssertEqual(store.dayIndex(of: place, stop: stop), 2)
        XCTAssertEqual(after.reduce(0) { $0 + $1.count }, before.reduce(0) { $0 + $1.count })
        // Diğer yerler günlerinde kalır.
        for (index, stops) in before.enumerated() {
            for other in stops where other.id != place.id {
                XCTAssertEqual(store.dayIndex(of: other, stop: stop), index, other.name)
            }
        }
        XCTAssertNotNil(store.undoMessage)

        store.undo()
        XCTAssertEqual(store.dayIndex(of: place, stop: stop), 0)
    }

    func testUserChoosesTheDay() throws {
        let store = makeStore()
        let stop = try tokyo(store)
        let first = try XCTUnwrap(store.dayPlan(stop: stop)[0].first)
        store.move(first, toDay: 1, stop: stop)

        // Gün seçilmezse 1. güne; seçilirse o güne eklenir (en yakın güne değil).
        let near = try XCTUnwrap(store.dayPlan(stop: stop)[2].first)
        let cafe = Place(name: "Yakın kafe", city: "Tokyo", latitude: near.latitude + 0.0004,
                         longitude: near.longitude, category: .cafe, source: .manual)
        store.add(cafe, plan: stop)
        XCTAssertEqual(store.dayIndex(of: cafe, stop: stop), 0)
        let bar = Place(name: "Bar", city: "Tokyo", latitude: 35.66, longitude: 139.70, category: .bar, source: .manual)
        store.add(bar, plan: stop, day: 2)
        XCTAssertEqual(store.dayIndex(of: bar, stop: stop), 2)
        store.removeFromPlan(cafe, stop: stop)
        store.addToPlan([cafe.id], stop: stop, day: 1)
        XCTAssertEqual(store.dayIndex(of: cafe, stop: stop), 1)
        XCTAssertEqual(store.dayIndex(of: first, stop: stop), 1)

        // Son gün silinince yerleri yeni son güne geçer; geri eklenen gün boştur.
        let planned = store.trip(stop: stop).placeIDs.count
        store.setDays(2, stop: stop)
        XCTAssertNotNil(store.undoMessage)
        XCTAssertEqual(store.dayIndex(of: bar, stop: stop), 1)
        XCTAssertEqual(store.dayPlan(stop: stop).reduce(0) { $0 + $1.count }, planned)
        store.setDays(3, stop: stop)
        XCTAssertEqual(store.dayPlan(stop: stop)[2].count, 0)
        XCTAssertEqual(store.dayIndex(of: first, stop: stop), 1)
    }

    /// Basılı tutup sürükleme: gün içinde sıra değişir, gün elle sıralı
    /// olur; başka günün yerine bırakılan yer o güne geçer.
    func testReorderWithinAndAcrossDays() throws {
        let store = makeStore()
        let stop = try tokyo(store)
        let day0 = store.dayPlan(stop: stop)[0]
        XCTAssertGreaterThan(day0.count, 1)
        let last = try XCTUnwrap(day0.last)
        XCTAssertFalse(store.isManuallyOrdered(day: 0, stop: stop))

        store.reorder(last, before: day0.first, day: 0, stop: stop)
        var updated = store.dayPlan(stop: stop)[0]
        XCTAssertEqual(updated.map(\.id), [last.id] + day0.dropLast().map(\.id))
        XCTAssertTrue(store.isManuallyOrdered(day: 0, stop: stop))
        XCTAssertNotNil(store.undoMessage)

        // Elle sıra kalıcı: yeni eklenen yer sona gelir.
        let cafe = Place(name: "Kafe", city: "Tokyo", latitude: 35.70, longitude: 139.77, category: .cafe, source: .manual)
        store.add(cafe, plan: stop)
        updated = store.dayPlan(stop: stop)[0]
        XCTAssertEqual(updated.first?.id, last.id)
        XCTAssertEqual(updated.last?.id, cafe.id)

        // 2. günün ilk yeri 1. günün ikinci sırasına.
        let moved = try XCTUnwrap(store.dayPlan(stop: stop)[1].first)
        store.reorder(moved, before: updated[1], day: 0, stop: stop)
        XCTAssertEqual(store.dayIndex(of: moved, stop: stop), 0)
        XCTAssertEqual(store.dayPlan(stop: stop)[0][1].id, moved.id)
        XCTAssertFalse(store.dayPlan(stop: stop)[1].contains { $0.id == moved.id })

        // Sona bırakma.
        store.reorder(last, before: nil, day: 0, stop: stop)
        XCTAssertEqual(store.dayPlan(stop: stop)[0].last?.id, last.id)

        // Yürüme sırasına dönüş elle sırayı bırakır; yerler günde kalır.
        let count = store.dayPlan(stop: stop)[0].count
        store.orderByWalking(day: 0, stop: stop)
        XCTAssertFalse(store.isManuallyOrdered(day: 0, stop: stop))
        XCTAssertEqual(store.dayPlan(stop: stop)[0].count, count)
    }

    /// Aynı şehir iki gezide olabilir; planları birbirine karışmaz.
    func testSameCityInTwoTripsKeepsSeparatePlans() throws {
        let store = makeStore()
        let first = try tokyo(store)
        let firstCount = store.trip(stop: first).placeIDs.count
        let tokyoChoice = CityChoice(name: "Tokyo", countryCode: "JP", latitude: 35.68, longitude: 139.76)
        let id = store.createJourney(name: "Tokyo yeniden", cities: [tokyoChoice])
        let second = try XCTUnwrap(store.journey(id)?.stops.first?.id)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(store.trip(stop: second).placeIDs.count, 0)

        let place = try XCTUnwrap(store.dayPlan(stop: first)[0].first)
        store.plan(place, stop: second, day: 1)
        XCTAssertEqual(store.dayIndex(of: place, stop: second), 1)
        XCTAssertEqual(store.dayIndex(of: place, stop: first), 0, "ilk gezideki günü değişmez")
        XCTAssertEqual(store.trip(stop: first).placeIDs.count, firstCount)
        XCTAssertEqual(store.plans(containing: place).count, 2)

        store.removeFromPlan(place, stop: second)
        XCTAssertTrue(store.isPlanned(place, stop: first))

        // Gezi silinince yalnızca onun planı gider.
        store.deleteJourney(id)
        XCTAssertEqual(store.trip(stop: first).placeIDs.count, firstCount)
    }

    /// Eski kayıt: planlar şehre bağlı. Açılınca şehri içeren her gezi
    /// şehrine kopyalanır, hiçbir yer kaybolmaz.
    func testOldCityPlansAttachToEveryTrip() throws {
        struct OldState: Encodable {
            var places: [Place]
            var trips: [Trip]
            var journeys: [Journey]
        }
        let places = SampleData.places
        let tokyoIDs = places.filter { $0.city == "Tokyo" }.map(\.id)
        let trip = Trip(city: "Tokyo", days: 3, placeIDs: tokyoIDs,
                        dayOf: Dictionary(uniqueKeysWithValues: tokyoIDs.enumerated().map { ($1, $0 % 3) }))
        let one = Journey(name: "Japonya", stops: [Destination(city: "Tokyo", latitude: 35.68, longitude: 139.76),
                                                   Destination(city: "Kyoto", latitude: 35.01, longitude: 135.77)])
        let two = Journey(name: "Tokyo yine", stops: [Destination(city: "Tokyo", latitude: 35.68, longitude: 139.76)])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(OldState(places: places, trips: [trip], journeys: [one, two])).write(to: url)

        let store = AppStore(fileURL: url)
        XCTAssertTrue(store.trips.allSatisfy { $0.stopID != nil })
        for stopID in [one.stops[0].id, two.stops[0].id] {
            XCTAssertEqual(store.trip(stop: stopID).placeIDs, tokyoIDs)
            XCTAssertEqual(store.trip(stop: stopID).days, 3)
        }
        XCTAssertEqual(store.trip(stop: one.stops[1].id).placeIDs, [])
        XCTAssertEqual(store.dayIndex(of: places[1], stop: two.stops[0].id), 1)

        // Bağlanmış hali kaydedilir: yeniden açılışta aynı.
        let reopened = AppStore(fileURL: url)
        XCTAssertEqual(reopened.trips.count, 3)
        XCTAssertEqual(reopened.trip(stop: one.stops[0].id).placeIDs, tokyoIDs)
    }

    /// "Yeni gezi" → koleksiyondan: koleksiyonun şehirleri durak, yerleri
    /// kendi şehrinin 1. gününde; ülkeler alınmaz, öteki geziler değişmez.
    func testTripFromCollection() throws {
        let store = makeStore()
        let sample = try tokyo(store)
        let sampleCount = store.trip(stop: sample).placeIDs.count
        let tokyoPlaces = Array(store.places(in: "Tokyo").prefix(3))
        let galata = try XCTUnwrap(store.places(in: "İstanbul").first)
        let id = store.createCollection(name: "Favoriler", emoji: "🍜", color: 2)
        for place in tokyoPlaces + [galata] { store.toggle(.place(place), in: id) }
        store.toggle(.city(CityChoice(name: "Kyoto", countryCode: "JP", latitude: 35.01, longitude: 135.77,
                                      englishTitle: "Kyoto")), in: id)
        if let japan = Country.find("JP") { store.toggle(.country(japan), in: id) }

        let journeyID = try XCTUnwrap(store.createJourney(from: id))
        let journey = try XCTUnwrap(store.journey(journeyID))
        XCTAssertEqual(journey.name, "Favoriler")
        XCTAssertEqual(journey.stops.map(\.city), ["Tokyo", "İstanbul", "Kyoto"])
        let tokyoStop = journey.stops[0].id
        XCTAssertEqual(Set(store.trip(stop: tokyoStop).placeIDs), Set(tokyoPlaces.map(\.id)))
        XCTAssertEqual(store.dayPlan(stop: tokyoStop)[0].count, 3)
        XCTAssertEqual(store.trip(stop: journey.stops[1].id).placeIDs, [galata.id])
        XCTAssertEqual(store.trip(stop: journey.stops[2].id).placeIDs, [])
        XCTAssertEqual(store.trip(stop: sample).placeIDs.count, sampleCount)
        XCTAssertEqual(store.collection(id)?.spots.count, 4, "yerler koleksiyonda kalır")

        store.undo()
        XCTAssertNil(store.journey(journeyID))
    }

    func testMovedDayPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let first = AppStore(fileURL: url)
        let stop = try tokyo(first)
        let place = try XCTUnwrap(first.dayPlan(stop: stop)[0].first)
        first.move(place, toDay: 1, stop: stop)

        let second = AppStore(fileURL: url)
        XCTAssertEqual(second.dayIndex(of: place, stop: stop), 1)
    }

    func testStatePersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let first = AppStore(fileURL: url)
        let place = Place(name: "Test", city: "Kyoto", latitude: 35.0, longitude: 135.7,
                          category: .temple, source: .manual)
        first.add(place)
        first.addToPlan([place.id], stop: first.planStop(for: "Kyoto"))

        let second = AppStore(fileURL: url)
        XCTAssertEqual(second.place(place.id)?.name, "Test")
        XCTAssertTrue(second.isPlanned(place))
        XCTAssertEqual(second.stops(in: "Kyoto").count, 1)
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

    func testCollections() throws {
        let store = makeStore()
        let place = try XCTUnwrap(store.places(in: "Tokyo").first)
        let id = store.createCollection(name: "İstanbul", emoji: "🌴", color: 0, with: .place(place))
        let city = CollectionItem.city(CityChoice(name: "Kyoto", countryCode: "JP", latitude: 35.0, longitude: 135.7,
                                                  englishTitle: "Kyoto"))
        store.toggle(city, in: id)
        XCTAssertEqual(store.collection(id)?.items.count, 2)
        XCTAssertEqual(store.collection(id)?.destinations.count, 1)
        XCTAssertEqual(store.collection(id)?.spots.count, 1)
        XCTAssertTrue(store.isCollected(.place(place)))

        // Aynı şehir ikinci kez eklenmez, çıkarılır.
        store.toggle(city, in: id)
        XCTAssertFalse(store.contains(city, in: id))

        store.deleteCollection(id)
        XCTAssertNil(store.collection(id))
        store.undo()
        XCTAssertNotNil(store.collection(id))
    }
}

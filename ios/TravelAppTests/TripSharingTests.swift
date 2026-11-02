import XCTest
@testable import TravelApp

/// Gezi paylaşımı: sunucuya giden içerik, arama metni, kopyalama ve
/// sunucudan gelen satırın okunması (internet gerekmez).
@MainActor
final class TripSharingTests: XCTestCase {
    private func makeStore() -> AppStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        return AppStore(fileURL: url)
    }

    /// Paylaşılan içerikte şehirler, günler ve yerler var; kişisel not yok.
    func testPayloadHasDaysAndPlacesButNoNotes() throws {
        let store = makeStore()
        let stop = try XCTUnwrap(store.stops(in: "Tokyo").first?.id)
        var place = try XCTUnwrap(store.dayPlan(stop: stop).first?.first)
        place.note = "kapı şifresi 1234"
        store.update(place)
        let journey = try XCTUnwrap(store.journeys.first { $0.stops.contains { $0.id == stop } })

        let payload = TripSharing.payload(for: journey, store: store)
        let tokyo = try XCTUnwrap(payload.stops.first { $0.city == "Tokyo" })
        XCTAssertEqual(tokyo.days, store.trip(stop: stop).days)
        XCTAssertEqual(tokyo.places.count, store.dayPlan(stop: stop).flatMap { $0 }.count)
        for (day, places) in store.dayPlan(stop: stop).enumerated() {
            XCTAssertEqual(tokyo.places.filter { $0.day == day }.map(\.name), places.map(\.name))
        }

        let row = TripSharing.row(for: journey, store: store, owner: UUID())
        let json = String(data: try JSONSerialization.data(withJSONObject: row.json), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("kapı şifresi"))
        XCTAssertEqual(row.json["place_count"] as? Int, tokyo.places.count)
    }

    /// Aynı gezi değişmeden yeniden hesaplanınca özet aynı; değişince farklı.
    func testRowHashChangesOnlyWithContent() throws {
        let store = makeStore()
        let journey = try XCTUnwrap(store.journeys.first)
        let first = TripSharing.row(for: journey, store: store, owner: UUID()).hash
        XCTAssertEqual(first, TripSharing.row(for: journey, store: store, owner: UUID()).hash)
        store.renameJourney(journey.id, to: "Japonya")
        let renamed = try XCTUnwrap(store.journey(journey.id))
        XCTAssertNotEqual(first, TripSharing.row(for: renamed, store: store, owner: UUID()).hash)
    }

    /// Arama: Türkçe ve İngilizce ülke adı, aksansız küçük harf.
    func testSearchTextFoldsTurkishAndEnglish() {
        let text = TripSharing.searchText(title: "İstanbul'da 3 gün", cities: ["İstanbul", "Kapadokya"],
                                          countryCodes: ["TR"])
        XCTAssertTrue(text.contains("istanbul"))
        XCTAssertTrue(text.contains("kapadokya"))
        XCTAssertTrue(text.contains("turkiye"))
        XCTAssertTrue(text.contains("turkey") || text.contains("turkiye"))
        XCTAssertEqual(text, text.lowercased())
    }

    /// Kopyalama: şehirler, gün sayıları ve yerler kendi günlerine gelir.
    func testCopySharedTripCreatesJourneyWithDays() throws {
        let store = makeStore()
        let shared = try XCTUnwrap(SampleData.sharedTrips().first)
        let before = store.journeys.count
        let id = try XCTUnwrap(store.copySharedTrip(shared))
        XCTAssertEqual(store.journeys.count, before + 1)
        let journey = try XCTUnwrap(store.journey(id))
        XCTAssertEqual(journey.name, shared.title)
        XCTAssertEqual(journey.stops.map(\.city), shared.cities)
        let payload = try XCTUnwrap(shared.data)
        for (index, stop) in payload.stops.enumerated() {
            let stopID = journey.stops[index].id
            XCTAssertEqual(store.trip(stop: stopID).days, stop.days)
            let plan = store.dayPlan(stop: stopID)
            for spot in stop.places {
                XCTAssertTrue(plan[spot.day].contains { $0.name == spot.name }, "\(spot.name) \(spot.day + 1). günde değil")
            }
        }
        XCTAssertNil(store.undoMessage)
    }

    /// Sunucudan gelen satır (profil adı ve simgesi iç içe).
    func testDecodesServerRow() throws {
        let json = """
        [{"id":"6c1d7a55-0f4b-4c1e-9b7b-2c9e8e1a0001","owner":"7a0e2b11-3c4d-4e5f-8a9b-0c1d2e3f4a01",
          "local_id":"6c1d7a55-0f4b-4c1e-9b7b-2c9e8e1a0009","title":"Japonya","cities":["Tokyo","Kyoto"],
          "country_codes":["JP"],"days":7,"place_count":12,"cover_title":null,
          "profiles":{"name":"Elif","emoji":"🌸"},
          "data":{"version":1,"stops":[{"city":"Tokyo","countryCode":"JP","latitude":35.6,"longitude":139.6,
            "days":4,"places":[{"name":"Sensō-ji","category":"temple","latitude":35.71,"longitude":139.79,"day":0},
                               {"name":"Yeni tür","category":"rocket","latitude":35.7,"longitude":139.7,"day":1}]}]}}]
        """
        let trips = try JSONDecoder().decode([SharedTrip].self, from: Data(json.utf8))
        let trip = try XCTUnwrap(trips.first)
        XCTAssertEqual(trip.author?.name, "Elif")
        XCTAssertEqual(trip.cities, ["Tokyo", "Kyoto"])
        XCTAssertNil(trip.coverTitle)
        let spots = try XCTUnwrap(trip.data?.stops.first?.places)
        XCTAssertEqual(spots.first?.placeCategory, .temple)
        // Bilinmeyen tür "Diğer" sayılır, gezi yine açılır.
        XCTAssertEqual(spots.last?.placeCategory, .other)
    }

    /// Örnek gezilerde arama: ülke adıyla da bulunur.
    func testSampleSearchMatchesCountryName() {
        XCTAssertEqual(SampleData.sharedTrips(matching: "japonya").count, 1)
        XCTAssertEqual(SampleData.sharedTrips(matching: "Italy").count, 1)
        XCTAssertEqual(SampleData.sharedTrips(matching: "").count, 3)
    }
}

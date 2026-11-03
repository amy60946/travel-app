import XCTest
@testable import TravelApp

/// Ek ücretsiz kaynaklar: Wikidata bilgileri, Wikivoyage gezgin notları,
/// Geoapify (OpenStreetMap) yakındaki yerler.
final class PlaceSourcesTests: XCTestCase {
    // MARK: - Wikidata

    func testParsesWikidataFacts() throws {
        let json = """
        {"id": "Q1053986",
         "descriptions": {"tr": {"language": "tr", "value": "İstanbul'da bir kule"}},
         "claims": {
           "P571": [{"rank": "normal", "mainsnak": {"datavalue": {"value": {"time": "+1110-00-00T00:00:00Z", "precision": 9}}}}],
           "P84": [{"rank": "normal", "mainsnak": {"datavalue": {"value": {"id": "Q42"}}}}],
           "P2048": [{"rank": "normal", "mainsnak": {"datavalue": {"value": {"amount": "+21", "unit": "http://www.wikidata.org/entity/Q11573"}}}}],
           "P1174": [{"rank": "deprecated", "mainsnak": {"datavalue": {"value": {"amount": "+1", "unit": "1"}}}},
                     {"rank": "preferred", "mainsnak": {"datavalue": {"value": {"amount": "+3500000", "unit": "1"}}}}],
           "P856": [{"rank": "normal", "mainsnak": {"datavalue": {"value": "https://kizkulesi.gov.tr"}}}],
           "P18": [{"rank": "normal", "mainsnak": {"datavalue": {"value": "Maiden's Tower in Istanbul.jpg"}}}]
         }}
        """
        let entity = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let (facts, linked) = WikidataService.parse(entity, language: "tr")
        XCTAssertEqual(facts.id, "Q1053986")
        XCTAssertEqual(facts.description, "İstanbul'da bir kule")
        XCTAssertEqual(facts.built, "1110")
        XCTAssertEqual(facts.height, 21)
        XCTAssertEqual(facts.visitorsPerYear, 3_500_000)
        XCTAssertEqual(facts.website?.host(), "kizkulesi.gov.tr")
        XCTAssertEqual(linked["P84"], ["Q42"])
        let image = try XCTUnwrap(facts.imageURL?.absoluteString)
        XCTAssertTrue(image.hasPrefix("https://commons.wikimedia.org/wiki/Special:FilePath/Maiden's_Tower_in_Istanbul.jpg"),
                      image)
        XCTAssertFalse(facts.isEmpty)
    }

    func testBuiltYears() {
        XCTAssertEqual(WikidataService.builtText("+1616-00-00T00:00:00Z", precision: 9, language: "tr"), "1616")
        XCTAssertEqual(WikidataService.builtText("-0410-00-00T00:00:00Z", precision: 9, language: "tr"), "MÖ 410")
        XCTAssertEqual(WikidataService.builtText("-0410-00-00T00:00:00Z", precision: 9, language: "en"), "410 BC")
        XCTAssertEqual(WikidataService.builtText("+1964-00-00T00:00:00Z", precision: 8, language: "tr"), "1960'lar")
        XCTAssertEqual(WikidataService.builtText("+1975-00-00T00:00:00Z", precision: 8, language: "tr"), "1970'ler")
        XCTAssertEqual(WikidataService.builtText("+1900-00-00T00:00:00Z", precision: 8, language: "tr"), "1900'ler")
        XCTAssertEqual(WikidataService.builtText("+1985-00-00T00:00:00Z", precision: 8, language: "en"), "1980s")
        // Yüzyıl kesinliğindeki tarih gösterilmez.
        XCTAssertNil(WikidataService.builtText("+1200-00-00T00:00:00Z", precision: 7, language: "tr"))
    }

    // MARK: - Wikivoyage

    private let wikitext = """
    ==See==
    * {{see
    | name=Maiden's Tower | alt=Kız Kulesi | url=http://www.kizkulesi.com.tr | email=
    | address= | lat=41.0211 | long=29.0041 | directions=on an islet off [[Üsküdar]]
    | phone= | hours=09:00-18:00 | price=''Ferry'' {{price|200 TL}}
    | content=A small '''tower''' on an islet, with a [[restaurant|café]] and views of the [[Bosphorus]].<ref>x</ref>
    }}
    * {{eat | name=Omoide Yokochō (Memory Lane) | lat= | long= | content=Tiny yakitori stalls under the tracks, smoky and lively.}}
    * {{do | name=Short | content=Too short.}}
    {{IsPartOf|Istanbul}}
    """

    func testParsesListings() {
        let listings = WikivoyageListings.parseListings(wikitext, article: "Istanbul/Üsküdar")
        XCTAssertEqual(listings.map(\.name), ["Maiden's Tower", "Omoide Yokochō (Memory Lane)"])
        let tower = listings[0]
        XCTAssertEqual(tower.kind, "see")
        XCTAssertEqual(tower.alt, "Kız Kulesi")
        XCTAssertEqual(tower.latitude, 41.0211)
        XCTAssertEqual(tower.longitude, 29.0041)
        XCTAssertEqual(tower.hours, "09:00-18:00")
        XCTAssertEqual(tower.price, "Ferry")
        XCTAssertEqual(tower.content, "A small tower on an islet, with a café and views of the Bosphorus.")
        XCTAssertEqual(tower.website?.host(), "www.kizkulesi.com.tr")
        XCTAssertNil(listings[1].latitude)
        XCTAssertEqual(tower.pageURL?.absoluteString, "https://en.wikivoyage.org/wiki/Istanbul/%C3%9Csk%C3%BCdar")
    }

    func testMatchesListingByNameAndDistance() {
        let listings = WikivoyageListings.parseListings(wikitext, article: "Istanbul")
        // Türkçe adla (alt) ve 300 m içinde.
        XCTAssertEqual(WikivoyageListings.bestMatch(listings, name: "Kız Kulesi", latitude: 41.0212, longitude: 29.0043)?.name,
                       "Maiden's Tower")
        // Aynı ad ama 2 km uzakta.
        XCTAssertNil(WikivoyageListings.bestMatch(listings, name: "Maiden's Tower", latitude: 41.04, longitude: 29.0))
        // Konumu olmayan listede ad birebir tutmalı (parantez ve harf farkı yok sayılır).
        XCTAssertEqual(WikivoyageListings.bestMatch(listings, name: "Omoide Yokocho", latitude: 35.69, longitude: 139.69)?.kind,
                       "eat")
        XCTAssertNil(WikivoyageListings.bestMatch(listings, name: "Omoide", latitude: 35.69, longitude: 139.69))
        // Uzaktaki konu sayfasında konumsuz liste kabul edilmez.
        XCTAssertNil(WikivoyageListings.bestMatch(listings, name: "Omoide Yokocho", latitude: 35.69, longitude: 139.69,
                                                  requiresLocation: true))
    }

    func testCleansWikiMarkup() {
        XCTAssertEqual(WikivoyageListings.plain("See [[Hagia Sophia|the church]] and [http://x.com the site] ''now''{{dead link}}."),
                       "See the church and the site now.")
    }

    // MARK: - Geoapify

    func testParsesGeoapifyPlaces() {
        let json = """
        {"type": "FeatureCollection", "features": [
          {"properties": {"name": "Fazıl Bey", "lat": 40.99, "lon": 29.03, "place_id": "a",
            "categories": ["catering", "catering.cafe"], "opening_hours": "Mo-Su 08:00-23:00",
            "datasource": {"raw": {"wikidata": "Q123", "website": "https://fazilbey.com"}}}},
          {"properties": {"name": "Yoğurtçu Parkı", "lat": 40.98, "lon": 29.03, "place_id": "b",
            "categories": ["leisure", "leisure.park"]}},
          {"properties": {"lat": 40.98, "lon": 29.03, "categories": ["catering.restaurant"]}}
        ]}
        """
        let spots = GeoapifyService.parse(Data(json.utf8))
        XCTAssertEqual(spots.map(\.name), ["Fazıl Bey", "Yoğurtçu Parkı"])
        XCTAssertEqual(spots[0].category, .cafe)
        XCTAssertEqual(spots[0].wikidata, "Q123")
        XCTAssertEqual(spots[0].website?.host(), "fazilbey.com")
        XCTAssertEqual(spots[1].category, .park)
        XCTAssertGreaterThan(spots[0].prominence, spots[1].prominence)
    }

    func testDropsNamesInUncommonScript() {
        func spot(_ name: String) -> GeoapifyService.Spot {
            GeoapifyService.Spot(id: name, name: name, latitude: 41, longitude: 29, category: .cafe,
                                 website: nil, openingHours: nil, wikidata: nil)
        }
        // İstanbul: Latin harfli adlar kalır, Arapça ad çıkar.
        let istanbul = GeoapifyService.readable([spot("Fazıl Bey"), spot("جلسة امام برج الفتاة (m&h)"),
                                                 spot("Korcan Aile Çay Bahçesi")])
        XCTAssertEqual(istanbul.map(\.name), ["Fazıl Bey", "Korcan Aile Çay Bahçesi"])
        XCTAssertEqual(GeoapifyService.script(of: "جلسة امام برج الفتاة (m&h)"), "arabic")
        XCTAssertEqual(GeoapifyService.script(of: "Café Ali"), "latin")
        // Tokyo: çoğunluk Japonca, Japonca adlar da Latin adlar da kalır.
        let tokyo = GeoapifyService.readable([spot("浅草寺"), spot("カフェ ムルソー"), spot("Fuglen Asakusa"), spot("上野公園")])
        XCTAssertEqual(tokyo.count, 4)
        XCTAssertEqual(GeoapifyService.script(of: "123 Café"), "latin")
        XCTAssertEqual(GeoapifyService.script(of: "Москва"), "cyrillic")
    }

    func testPicksNearAndKnownSpots() {
        func spot(_ name: String, _ lat: Double, _ category: PlaceCategory, wikidata: String? = nil) -> GeoapifyService.Spot {
            GeoapifyService.Spot(id: name, name: name, latitude: lat, longitude: 29.0, category: category,
                                 website: nil, openingHours: nil, wikidata: wikidata)
        }
        let anchor = Place(name: "Kız Kulesi", city: "İstanbul", latitude: 41.0, longitude: 29.0,
                           category: .viewpoint, source: .search)
        let spots = [
            spot("Uzak Kafe", 41.03, .cafe),                       // ~3,3 km: önerilmez
            spot("Sıradan Kafe", 41.001, .cafe),
            spot("Ünlü Kafe", 41.003, .cafe, wikidata: "Q1"),
            spot("Rotadaki Lokanta", 41.001, .food),
            spot("Park 1", 41.0015, .park), spot("Park 2", 41.002, .park), spot("Park 3", 41.0025, .park),
        ]
        let picked = GeoapifyService.pick(spots, anchors: [anchor]) { $0.name == "Rotadaki Lokanta" }
        XCTAssertEqual(picked.map(\.name), ["Ünlü Kafe", "Sıradan Kafe", "Park 1", "Park 2"])
    }
}

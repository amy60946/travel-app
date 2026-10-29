import XCTest
@testable import TravelApp

/// Wikivoyage'dan şehir listesi ve rehber bölümleri ayrıştırma.
final class DiscoverParserTests: XCTestCase {
    func testCityListFromBulletsAndMarkers() {
        let wikitext = """
        {{pagebanner|Japan banner.jpg}}
        ==Regions==
        * [[Hokkaido]] — not a city
        ==Cities==
        [[File:Tokyo.jpg|thumb|A [[Tokyo]] street]]
        * {{marker|type=city|name=[[Tokyo]]|lat=35.6895|long=139.6917|wikidata=Q1490}} — the capital, a mix of '''ultra-modern''' and traditional
        * [[Kyoto]] – the former capital, home to [[Kinkaku-ji|Kinkaku]]<ref>note</ref>
        * [[Nara (city)|Nara]] - ancient temples and deer
        ==Other destinations==
        * [[Mount Fuji]]
        """
        let cities = DiscoverService.cityList(fromWikitext: wikitext)
        XCTAssertEqual(cities.map(\.title), ["Tokyo", "Kyoto", "Nara (city)"])
        XCTAssertEqual(cities.map(\.name), ["Tokyo", "Kyoto", "Nara"])
        XCTAssertEqual(cities[0].summary, "the capital, a mix of ultra-modern and traditional")
        XCTAssertEqual(cities[0].latitude ?? 0, 35.6895, accuracy: 0.0001)
        XCTAssertEqual(cities[0].longitude ?? 0, 139.6917, accuracy: 0.0001)
        XCTAssertEqual(cities[1].summary, "the former capital, home to Kinkaku")
        XCTAssertNil(cities[1].latitude)
        XCTAssertEqual(cities[2].summary, "ancient temples and deer")
    }

    func testCityListFromCitylistTemplate() {
        let wikitext = """
        == Cities ==
        {{Citylist
        | 1={{marker|type=city|name=[[Paris]]|lat=48.8566|long=2.3522}} — the "City of Light"
        | 2={{marker|type=city|name=[[Bordeaux]]}} — wine capital
        }}
        """
        let cities = DiscoverService.cityList(fromWikitext: wikitext)
        XCTAssertEqual(cities.map(\.name), ["Paris", "Bordeaux"])
        XCTAssertEqual(cities[1].summary, "wine capital")
    }

    func testGuideSections() {
        let extract = """
        Kyoto is a city in Japan.

        == Understand ==
        Kyoto was the capital for a thousand years.

        === Climate ===
        Summers are hot and humid.

        == Get in ==

        === By plane ===
        The nearest airport is Kansai.

        == See ==
        Temples.

        == Stay safe ==
        Kyoto is very safe.
        """
        let sections = DiscoverService.guideSections(fromExtract: extract)
        XCTAssertEqual(sections.map(\.heading), ["Understand", "Climate", "Get in", "Stay safe"])
        XCTAssertEqual(sections[0].text, "Kyoto was the capital for a thousand years.")
        XCTAssertEqual(sections[2].text, "The nearest airport is Kansai.")
    }

    func testExcerptCutsLongText() {
        let sentence = String(repeating: "word ", count: 30) + "end. "
        let long = String(repeating: sentence, count: 10)
        let excerpt = DiscoverService.excerpt(long, limit: 300)
        XCTAssertLessThanOrEqual(excerpt.count, 600)
        XCTAssertTrue(excerpt.hasSuffix("."))
    }
}

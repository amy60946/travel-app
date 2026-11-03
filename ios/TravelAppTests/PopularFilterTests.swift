import XCTest
@testable import TravelApp

final class PopularFilterTests: XCTestCase {
    func testKeepsSightsAndDropsInstitutions() {
        XCTAssertTrue(WikipediaService.isSight("Sensō-ji"))
        XCTAssertTrue(WikipediaService.isSight("Nippon Budokan"))
        XCTAssertFalse(WikipediaService.isSight("Sophia University"))
        XCTAssertFalse(WikipediaService.isSight("Ichigaya Station"))
        XCTAssertFalse(WikipediaService.isSight("Chongryon"))
        XCTAssertFalse(WikipediaService.isSight("Empire of Japan"))
    }

    func testDropsCountriesCitiesAndStationsByTypeAndDescription() {
        XCTAssertTrue(WikipediaService.isSight(type: nil))
        XCTAssertTrue(WikipediaService.isSight(type: "landmark"))
        XCTAssertFalse(WikipediaService.isSight(type: "country"))
        XCTAssertFalse(WikipediaService.isSight(type: "city(13960000)"))
        XCTAssertFalse(WikipediaService.isSight(type: "railwaystation"))
        XCTAssertTrue(WikipediaService.isSight(description: nil))
        XCTAssertTrue(WikipediaService.isSight(description: "Buddhist temple in Asakusa, Tokyo, Japan"))
        XCTAssertTrue(WikipediaService.isSight(description: "Headquarters of the Tokyo Metropolitan Government"))
        XCTAssertFalse(WikipediaService.isSight(description: "Japanese state from 1868 to 1947"))
        XCTAssertFalse(WikipediaService.isSight(description: "Island country in East Asia"))
        XCTAssertFalse(WikipediaService.isSight(description: "Railway station in Tokyo, Japan"))
        // Kız Kulesi çevresi (Wikipedia, 2026-11-03)
        XCTAssertTrue(WikipediaService.isSight(description: "16th century Turkish mosque"))
        XCTAssertTrue(WikipediaService.isSight(description: "Fountain in Istanbul, Turkey"))
        XCTAssertFalse(WikipediaService.isSight(description: "Quarter in Marmara, Turkey"))
        XCTAssertFalse(WikipediaService.isSight(description: "Neighbourhood in Istanbul, Turkey"))
        XCTAssertFalse(WikipediaService.isSight(description: "District and municipality in Istanbul, Turkey"))
        XCTAssertFalse(WikipediaService.isSight(description: "Prison in Turkey"))
        XCTAssertFalse(WikipediaService.isSight(description: "Ferry terminal in Üsküdar, Istanbul"))
        XCTAssertFalse(WikipediaService.isSight(description: "Station of the Istanbul Metro"))
        XCTAssertFalse(WikipediaService.isSight(description: "Train stop in eastern Istanbul"))
    }
}

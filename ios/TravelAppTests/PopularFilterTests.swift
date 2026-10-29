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
    }
}

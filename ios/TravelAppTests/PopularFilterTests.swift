import XCTest
@testable import TravelApp

final class PopularFilterTests: XCTestCase {
    func testKeepsSightsAndDropsInstitutions() {
        XCTAssertTrue(WikipediaService.isSight("Sensō-ji"))
        XCTAssertTrue(WikipediaService.isSight("Nippon Budokan"))
        XCTAssertFalse(WikipediaService.isSight("Sophia University"))
        XCTAssertFalse(WikipediaService.isSight("Ichigaya Station"))
        XCTAssertFalse(WikipediaService.isSight("Chongryon"))
    }
}

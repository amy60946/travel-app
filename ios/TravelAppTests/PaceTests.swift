import XCTest
@testable import TravelApp

final class PaceTests: XCTestCase {
    func testStopsGrowWithPace() {
        XCTAssertLessThan(Pace.relaxed.stopsPerDay.upperBound, Pace.normal.stopsPerDay.lowerBound)
        XCTAssertLessThan(Pace.normal.stopsPerDay.upperBound, Pace.brisk.stopsPerDay.lowerBound)
    }

    func testMaxStops() {
        XCTAssertEqual(Pace.normal.maxStops(days: 3), 18)
        XCTAssertEqual(Pace.relaxed.maxStops(days: 0), 0)
    }
}

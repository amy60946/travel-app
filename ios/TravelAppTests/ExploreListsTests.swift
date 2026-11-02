import XCTest
@testable import TravelApp

final class ExploreListsTests: XCTestCase {
    func testInterestSplitsLastThirtyDays() {
        var daily: [String: Int?] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let start = formatter.date(from: "2026-09-01")!
        for day in 0..<60 {
            let key = formatter.string(from: start.addingTimeInterval(Double(day) * 86_400))
            daily[key] = day < 30 ? 10 : 20
        }
        daily[formatter.string(from: start.addingTimeInterval(59 * 86_400))] = .some(nil)
        let interest = ExploreLists.interest(daily: daily)
        XCTAssertEqual(interest.previous, 300)
        XCTAssertEqual(interest.recent, 29 * 20, "verisi olmayan gün sayılmaz")
        XCTAssertGreaterThan(interest.growth, 1.9)
    }

    func testSectionsDoNotRepeatCountries() {
        let countries = Array(Country.all.prefix(40))
        var interest: [String: ExploreLists.Interest] = [:]
        for (index, country) in countries.enumerated() {
            // Çok okunan ilk ülkeler sabit; arkadakilerin ilgisi artıyor.
            interest[country.title] = .init(recent: 10_000 - index * 200, previous: index < 20 ? 10_000 - index * 200 : 2_000)
        }
        let shown: Set<String> = [countries[0].code]
        let lists = ExploreLists.make(interest, countries: countries, excluding: shown)
        XCTAssertEqual(lists.popular.count, 10)
        XCTAssertEqual(lists.popular.first, countries[1], "Senin için'deki ülke tekrar edilmez")
        XCTAssertEqual(lists.trending.count, 6)
        XCTAssertFalse(lists.underRadar.isEmpty)
        let all = lists.all.map(\.code)
        XCTAssertEqual(all.count, Set(all).count, "bir ülke yalnızca bir bölümde")
        XCTAssertFalse(all.contains(countries[0].code))
        // İlgisi en çok artan (arkadaki) ülkeler yükselenlerde.
        XCTAssertTrue(lists.trending.allSatisfy { countries.firstIndex(of: $0)! >= 20 })
    }

    func testEmptyWithoutData() {
        XCTAssertTrue(ExploreLists.make([:]).isEmpty)
    }
}

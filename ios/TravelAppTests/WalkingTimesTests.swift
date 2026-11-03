import CoreLocation
import XCTest
@testable import TravelApp

/// Gerçek yürüme süreleri (Geoapify Route Matrix): cevabı okuma, kredi,
/// hangi çiftlerin sorulacağı, gün planı ve önerilerde kullanılması.
final class WalkingTimesTests: XCTestCase {
    func testParsesMatrixWithMissingRoute() throws {
        let json = """
        {"sources_to_targets": [
          [{"distance": 0, "time": 0, "source_index": 0, "target_index": 0},
           {"distance": 1450, "time": 1100, "source_index": 0, "target_index": 1}],
          [{"distance": null, "time": null, "source_index": 1, "target_index": 0},
           {"distance": 0, "time": 0, "source_index": 1, "target_index": 1}]
        ]}
        """
        let matrix = try XCTUnwrap(GeoapifyService.parseMatrix(Data(json.utf8), sources: 2, targets: 2))
        XCTAssertEqual(matrix[0][1], WalkLeg(meters: 1450, seconds: 1100))
        XCTAssertNil(matrix[1][0])
        // Dakika yolun uzunluğundan, dakikada 80 m.
        XCTAssertEqual(matrix[0][1]?.minutes ?? 0, 1450.0 / 80, accuracy: 0.01)
        XCTAssertNil(GeoapifyService.parseMatrix(Data("{}".utf8), sources: 1, targets: 1))
    }

    func testMatrixCredits() {
        XCTAssertEqual(GeoapifyService.matrixCredits(sources: 8, targets: 8), 64)
        XCTAssertEqual(GeoapifyService.matrixCredits(sources: 1, targets: 8), 8)
        XCTAssertEqual(GeoapifyService.matrixCredits(sources: 26, targets: 3), 78)
        XCTAssertEqual(GeoapifyService.matrixCredits(sources: 30, targets: 30), 300)
    }

    func testAsksOnlyMissingPairs() {
        // İlk kez dört yer: üç nokta bütün çiftlere dokunur.
        let all = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
        XCTAssertEqual(WalkingTimes.cover(all), [0, 1, 2])
        // Güne yeni eklenen 3. yer: yalnızca onun satırı.
        XCTAssertEqual(WalkingTimes.cover([(0, 3), (1, 3), (2, 3)]), [3])
        XCTAssertEqual(WalkingTimes.cover([]), [])
    }

    func testPairKeyIsTheSameBothWays() {
        let a = CLLocationCoordinate2D(latitude: 41.02111, longitude: 29.00417)
        let b = CLLocationCoordinate2D(latitude: 41.0262, longitude: 29.0101)
        XCTAssertEqual(WalkingTimes.key(a, b), WalkingTimes.key(b, a))
        XCTAssertEqual(WalkingTimes.unique([a, b, a]).count, 2)
    }

    func testDayPlannerUsesRealWalks() {
        func stop(_ offset: Double) -> DayPlanner.Stop {
            DayPlanner.Stop(id: UUID(), latitude: 41.0 + offset, longitude: 29.0, category: .sight,
                            visitMinutes: 30, pinned: nil)
        }
        let a = stop(0), b = stop(0.002), c = stop(0.004)
        var walks = DayPlanner.Walks()
        // Kuş uçuşu ~220 m (~4 dk) ama arada su var: yürüyerek 40 dk.
        walks.minutes[.init(from: a.id, to: b.id)] = 40
        walks.minutes[.init(from: b.id, to: a.id)] = 40
        XCTAssertEqual(DayPlanner.legMinutes([a, b], walks: walks), [40])
        XCTAssertLessThan(DayPlanner.legMinutes([a, b])[0], 5)
        XCTAssertEqual(DayPlanner.totalMinutes([a, b], walks: walks), 30 + 40 + 30)
        // Bilinmeyen bacak tahminle.
        XCTAssertLessThan(DayPlanner.legMinutes([b, c], walks: walks)[0], 5)
    }

    func testSmartOrderAvoidsLongRealWalk() {
        func stop(_ latitude: Double) -> DayPlanner.Stop {
            DayPlanner.Stop(id: UUID(), latitude: latitude, longitude: 29.0, category: .sight,
                            visitMinutes: 30, pinned: nil)
        }
        // Kuş uçuşu sıra a → b → c; ama a ile b arası yürüyerek çok uzun.
        let a = stop(41.000), b = stop(41.003), c = stop(41.006)
        var walks = DayPlanner.Walks()
        for (x, y, minutes) in [(a, b, 60.0), (b, c, 5), (a, c, 8)] {
            walks.minutes[.init(from: x.id, to: y.id)] = minutes
            walks.minutes[.init(from: y.id, to: x.id)] = minutes
        }
        let plain = DayPlanner.smartOrders([a, b, c]).first?.map(\.id)
        let walked = DayPlanner.smartOrders([a, b, c], walks: walks).first?.map(\.id)
        XCTAssertNotNil(plain)
        // a ile b yan yana gelmez.
        if let order = walked, let ia = order.firstIndex(of: a.id), let ib = order.firstIndex(of: b.id) {
            XCTAssertNotEqual(abs(ia - ib), 1, "a ve b arası 60 dk yürüme")
        } else {
            XCTFail("sıra yok")
        }
    }

    func testSuggestionsFollowRealWalks() {
        let tower = Place(name: "Kız Kulesi", city: "İstanbul", latitude: 41.02111, longitude: 29.00417,
                          category: .viewpoint, source: .search)
        let salacak = Place(name: "Salacak", city: "İstanbul", latitude: 41.0245, longitude: 29.0070,
                            category: .viewpoint, source: .search)
        func suggestion(_ title: String, _ latitude: Double, _ longitude: Double, score: Double) -> Recommender.Suggestion {
            let place = WikipediaService.PopularPlace(title: title, latitude: latitude, longitude: longitude,
                                                      monthlyViews: 1000, thumbnailURL: nil, localTitle: nil)
            let distance = tower.location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
            return Recommender.Suggestion(place: place, category: .sight, anchorName: "Kız Kulesi",
                                          distance: distance, score: score)
        }
        let across = suggestion("Karşı Yaka", 41.032, 28.995, score: 1.0)   // kuş uçuşu ~1,4 km, karşı kıyı
        let mosque = suggestion("Şemsi Paşa Camii", 41.0262, 29.0101, score: 0.6)
        let unknown = suggestion("Bilinmeyen", 41.0230, 29.0080, score: 0.5)
        let walks: [String: WalkLeg] = [
            "Karşı Yaka|Kız Kulesi": WalkLeg(meters: 9000, seconds: 6600),     // 110 dk: çıkar
            "Şemsi Paşa Camii|Kız Kulesi": WalkLeg(meters: 1400, seconds: 1080),
            "Şemsi Paşa Camii|Salacak": WalkLeg(meters: 600, seconds: 720),    // en kısa: 7,5 dk
        ]
        let result = Recommender.applyingWalks([across, mosque, unknown], anchors: [tower, salacak]) { anchor, point in
            let title = [across, mosque, unknown].first {
                abs($0.place.latitude - point.latitude) < 1e-9 && abs($0.place.longitude - point.longitude) < 1e-9
            }?.place.title ?? ""
            return walks["\(title)|\(anchor.name)"]
        }
        XCTAssertEqual(result.map(\.place.title), ["Şemsi Paşa Camii", "Bilinmeyen"])
        XCTAssertEqual(result[0].anchorName, "Salacak")
        XCTAssertEqual(result[0].walkingMinutes, 8)
        XCTAssertNil(result[1].walkSeconds)
    }
}

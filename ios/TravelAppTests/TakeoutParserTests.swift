import XCTest
@testable import TravelApp

final class TakeoutParserTests: XCTestCase {
    func testSavedPlacesGeoJSON() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"geometry":{"coordinates":[139.7967,35.7148],"type":"Point"},
           "properties":{"date":"2025-01-01","google_maps_url":"http://maps.google.com/?cid=1",
             "location":{"name":"Sensō-ji","address":"2 Chome-3-1 Asakusa, Taito City, Tokyo","country_code":"JP"}},
           "type":"Feature"},
          {"geometry":{"coordinates":[0,0],"type":"Point"},
           "properties":{"google_maps_url":"https://www.google.com/maps/place/Galata+Tower/@41.0256,28.9741,17z",
             "location":{"name":"Galata Kulesi"}},
           "type":"Feature"},
          {"geometry":{"coordinates":[0,0],"type":"Point"},
           "properties":{"location":{"name":"Bilinmeyen Kafe"}}, "type":"Feature"}
        ]}
        """
        let items = TakeoutParser.parse(data: Data(json.utf8), fileName: "Saved Places.json")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].name, "Sensō-ji")
        XCTAssertEqual(items[0].latitude, 35.7148)
        XCTAssertEqual(items[0].longitude, 139.7967)
        // [0, 0] yerine linkteki koordinat kullanılır.
        XCTAssertEqual(items[1].latitude, 41.0256)
        XCTAssertEqual(items[1].longitude, 28.9741)
        // Koordinatsız: aranacak.
        XCTAssertFalse(items[2].hasCoordinate)
        XCTAssertTrue(items.allSatisfy { $0.source == .googleMaps })
    }

    func testListCSV() {
        let csv = """
        Title,Note,URL,Tags,Comment
        ,,,,
        Omoide Yokochō,"Akşam, yakitori",https://www.google.com/maps/place/Omoide+Yokocho/data=!4m2!3m1!1s0x0:0x1,,
        "Tsukiji ""dış"" pazarı",,https://www.google.com/maps/place/Tsukiji/data=!3m1!4b1!4m6!3m5!8m2!3d35.6655!4d139.7707,,
        """
        let items = TakeoutParser.parse(data: Data(csv.utf8), fileName: "Want to go.csv")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "Omoide Yokochō")
        XCTAssertEqual(items[0].note, "Akşam, yakitori")
        XCTAssertFalse(items[0].hasCoordinate)
        XCTAssertEqual(items[1].name, "Tsukiji \"dış\" pazarı")
        XCTAssertEqual(items[1].latitude, 35.6655)
        XCTAssertEqual(items[1].longitude, 139.7707)
    }

    func testCoordinateFromLinks() {
        let at = URL(string: "https://www.google.com/maps/place/X/@35.1,139.2,15z")!
        XCTAssertEqual(TakeoutParser.coordinate(fromMapsURL: at)?.latitude, 35.1)
        let query = URL(string: "https://maps.google.com/?q=41.01,28.97")!
        XCTAssertEqual(TakeoutParser.coordinate(fromMapsURL: query)?.longitude, 28.97)
        XCTAssertNil(TakeoutParser.coordinate(fromMapsURL: URL(string: "https://maps.google.com/?cid=123")!))
    }

    func testPlaceNameFromLink() {
        let url = URL(string: "https://www.google.com/maps/place/Sens%C5%8D-ji/@35.7,139.7,17z")!
        XCTAssertEqual(TakeoutParser.placeName(fromMapsURL: url), "Sensō-ji")
        let plus = URL(string: "https://www.google.com/maps/place/Galata+Tower/data=!4m2")!
        XCTAssertEqual(TakeoutParser.placeName(fromMapsURL: plus), "Galata Tower")
    }
}

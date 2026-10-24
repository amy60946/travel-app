import XCTest
@testable import TravelApp

final class SocialExportTests: XCTestCase {
    private func parse(_ text: String, _ fileName: String) -> [SocialExport.Post] {
        SocialExport.parse(data: Data(text.utf8), fileName: fileName)
    }

    func testInstagramSavedPosts() {
        let json = """
        {"saved_saved_media": [
          {"title": "afuri_official", "string_map_data": {"Saved on": {"href": "https://www.instagram.com/p/ABC123/", "timestamp": 1690000000}}},
          {"title": "tokyofoodie", "string_map_data": {"Saved on": {"href": "https://www.instagram.com/reel/XYZ789/", "timestamp": 1690000001}}}
        ]}
        """
        let posts = parse(json, "saved_posts.json")
        XCTAssertEqual(posts.map(\.author), ["afuri_official", "tokyofoodie"])
        XCTAssertEqual(posts.map(\.source), [.instagram, .instagram])
        XCTAssertEqual(posts.first?.url.absoluteString, "https://www.instagram.com/p/ABC123/")
    }

    func testInstagramCollectionsKeepCollectionName() {
        let json = """
        {"saved_saved_collections": [
          {"title": "Collection", "string_map_data": {"Name": {"value": "Tokyo"}, "Creation Time": {"timestamp": 1}, "Update Time": {"timestamp": 2}}},
          {"string_map_data": {"Name": {"value": "ichiran_jp", "href": "https://www.instagram.com/p/AAA/"}, "Added Time": {"timestamp": 3}}},
          {"title": "Collection", "string_map_data": {"Name": {"value": "Kyoto"}, "Creation Time": {"timestamp": 4}}},
          {"string_map_data": {"Name": {"value": "fushimi", "href": "https://www.instagram.com/p/BBB/"}, "Added Time": {"timestamp": 5}}}
        ]}
        """
        let posts = parse(json, "saved_collections.json")
        XCTAssertEqual(posts.map(\.collection), ["Tokyo", "Kyoto"])
        XCTAssertEqual(posts.map(\.author), ["ichiran_jp", "fushimi"])
    }

    func testInstagramLabelValuesFormat() {
        let json = """
        [{"timestamp": 1, "label_values": [
          {"label": "URL", "value": "https://www.instagram.com/p/CCC/"},
          {"label": "Owner", "dict": [{"dict": [{"label": "Name", "value": "Blue Bottle Coffee"}, {"label": "Username", "value": "bluebottle"}]}]}
        ]}]
        """
        let posts = parse(json, "saved_posts.json")
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.author, "bluebottle")
    }

    func testTikTokTakesOnlyFavorites() {
        let json = """
        {"Activity": {
          "Favorite Videos": {"FavoriteVideoList": [
            {"Date": "2026-01-01 10:00:00", "Link": "https://www.tiktokv.com/share/video/7212345678901234567/"}
          ]},
          "Video Browsing History": {"VideoList": [
            {"Date": "2026-01-02 10:00:00", "Link": "https://www.tiktokv.com/share/video/7000000000000000001/"}
          ]},
          "Like List": {"ItemFavoriteList": [
            {"Date": "2026-01-03", "Link": "https://www.tiktokv.com/share/video/7000000000000000002/"}
          ]}
        }}
        """
        let posts = parse(json, "user_data_tiktok.json")
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.source, .tiktok)
        XCTAssertEqual(posts.first.flatMap { SocialExport.tiktokVideoID(in: $0.url) }, "7212345678901234567")
    }

    func testTikTokTextFavoritesSection() {
        let text = """
        Video Browsing History:
        Date: 2026-01-02 10:00:00
        Link: https://www.tiktokv.com/share/video/7000000000000000001/

        Favorite Videos:
        Date: 2026-01-01 10:00:00
        Link: https://www.tiktokv.com/share/video/7212345678901234567/
        """
        let posts = parse(text, "user_data.txt")
        XCTAssertEqual(posts.map { SocialExport.canonical($0.url) }, ["tiktok:7212345678901234567"])
    }

    func testHTMLSavedFileAndDuplicates() {
        let html = """
        <div><a href="https://www.instagram.com/p/DDD/">x</a><a href="https://www.instagram.com/p/DDD/?igsh=1">y</a>
        <a href="https://www.instagram.com/someone/">profile</a></div>
        """
        let posts = parse(html, "saved_posts.html")
        XCTAssertEqual(posts.count, 1)
    }

    func testBatchResultsParse() {
        let text = #"{"results": [{"index": 1, "places": [{"name": "Afuri Ebisu", "city": "Tokyo"}]}, {"index": 9, "places": [{"name": "x"}]}]}"#
        let results = PlaceAI.parse(results: text, count: 2)
        XCTAssertEqual(results[0], [])
        XCTAssertEqual(results[1], [.init(name: "Afuri Ebisu", city: "Tokyo")])
    }
}

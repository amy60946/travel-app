import XCTest
@testable import TravelApp

final class ExportFilesTests: XCTestCase {
    /// Python zipfile ile üretildi: kayıtlılar (deflate), bir mesaj dosyası
    /// (deflate), bir fotoğraf (sıkıştırmasız) ve bir klasör kaydı.
    private let instagramZip = Data(base64Encoded: "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")!

    private let savedPosts = #"{"saved_saved_media": [{"title": "afuri_official", "string_map_data": {"Saved on": {"href": "https://www.instagram.com/p/ABC123/", "timestamp": 1690000000}}}, {"title": "tokyofoodie", "string_map_data": {"Saved on": {"href": "https://www.instagram.com/reel/XYZ789/", "timestamp": 1690000001}}}]}"#

    func testZipReaderListsFilesAndInflates() throws {
        let zip = try XCTUnwrap(ZipReader(data: instagramZip))
        XCTAssertEqual(zip.entries.map(\.path), [
            "your_instagram_activity/saved/saved_posts.json",
            "your_instagram_activity/messages/inbox/a/message_1.json",
            "media/posts/photo.jpg",
        ])
        let saved = try XCTUnwrap(zip.contents(of: zip.entries[0]))
        XCTAssertEqual(String(decoding: saved, as: UTF8.self), savedPosts)
        let photo = try XCTUnwrap(zip.contents(of: zip.entries[2]))
        XCTAssertEqual(photo, Data((0..<1024).map { UInt8($0 % 256) }))
    }

    func testZipReaderRejectsOtherData() {
        XCTAssertNil(ZipReader(data: Data("not a zip".utf8)))
    }

    func testZipKeepsOnlySavedFiles() {
        let files = ExportFiles.files(in: instagramZip, name: "instagram-oguz-2026-10-24-abc.zip")
        XCTAssertEqual(files.map(\.name), ["your_instagram_activity/saved/saved_posts.json"])
        let posts = SocialExport.posts(in: files)
        XCTAssertEqual(posts.map(\.author), ["afuri_official", "tokyofoodie"])
    }

    func testPlainFileIsReadAsIs() {
        let files = ExportFiles.files(in: Data(savedPosts.utf8), name: "saved_posts.json")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(SocialExport.posts(in: files).count, 2)
    }

    func testLoadFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("instagram-test.zip")
        try instagramZip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ExportFiles.load([url]).count, 1)
    }

    func testExportNames() {
        XCTAssertTrue(ExportFiles.isExportName("instagram-oguz-2026-10-24-AbCd.zip"))
        XCTAssertTrue(ExportFiles.isExportName("TikTok_Data_1729771234.zip"))
        XCTAssertTrue(ExportFiles.isExportName("user_data_tiktok.json"))
        XCTAssertTrue(ExportFiles.isExportName("takeout-20261024T101010Z-001.zip"))
        XCTAssertFalse(ExportFiles.isExportName("IMG_0830.png"))
        XCTAssertFalse(ExportFiles.isExportName("rapor.zip"))
    }

    func testRelevantPaths() {
        XCTAssertTrue(ExportFiles.isRelevant("your_instagram_activity/saved/saved_collections.json"))
        XCTAssertTrue(ExportFiles.isRelevant("Takeout/Maps (your places)/Saved Places.json"))
        XCTAssertTrue(ExportFiles.isRelevant("Takeout/Saved/Want to go.csv"))
        XCTAssertTrue(ExportFiles.isRelevant("user_data_tiktok.json"))
        XCTAssertTrue(ExportFiles.isRelevant("TikTok/Activity/Favorite Videos.txt"))
        XCTAssertFalse(ExportFiles.isRelevant("your_instagram_activity/messages/inbox/a/message_1.json"))
        XCTAssertFalse(ExportFiles.isRelevant("your_instagram_activity/likes/liked_posts.json"))
        XCTAssertFalse(ExportFiles.isRelevant("media/posts/photo.jpg"))
    }
}

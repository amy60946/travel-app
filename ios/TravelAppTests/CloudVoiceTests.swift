import XCTest
@testable import TravelApp

/// Google sesi: yazının parçalara bölünmesi ve telefon başına harf sınırı.
final class CloudVoiceTests: XCTestCase {
    private func covered(_ ranges: [NSRange]) -> Int { ranges.reduce(0) { $0 + $1.length } }

    func testShortTextIsOneSegment() {
        let text = "Kız Kulesi, Üsküdar açıklarında küçük bir adacıkta bulunan bir kuledir."
        XCTAssertEqual(Narrator.voiceSegments(of: text), [NSRange(location: 0, length: (text as NSString).length)])
    }

    func testLongTextSplitsAtSentenceEnds() {
        let text = String(repeating: "Bu yapı Bizans döneminde yapılmıştır. ", count: 120)
        let source = text as NSString
        let segments = Narrator.voiceSegments(of: text)
        XCTAssertGreaterThan(segments.count, 3)
        XCTAssertLessThanOrEqual(segments[0].length, 250)
        XCTAssertTrue(segments.dropFirst().allSatisfy { $0.length <= 1500 })
        // Parçalar arka arkaya, boşluk bırakmadan bütün yazıyı kaplar.
        for (previous, next) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(previous.location + previous.length, next.location)
        }
        XCTAssertEqual(covered(segments), source.length)
        // Her parça (sonuncusu hariç) cümle sonunda biter.
        for segment in segments.dropLast() {
            XCTAssertTrue(source.substring(with: segment).hasSuffix(". "))
        }
    }

    func testChapterStartsBeginNewSegments() {
        let text = "Özet metni.\n\nTarihçe.\nEski bir kuledir."
        let chapter = ("Özet metni.\n\n" as NSString).length
        let segments = Narrator.voiceSegments(of: text, breaks: [0, chapter])
        XCTAssertEqual(segments.map(\.location), [0, chapter])
        XCTAssertEqual(covered(segments), (text as NSString).length)
    }

    func testAppendedTextSkipsBlankJoint() {
        let summary = "Özet metni."
        let text = summary + "\n\nTarihçe.\nEski bir kuledir."
        let chapter = (summary as NSString).length + 2
        let added = Narrator.voiceSegments(of: text, from: (summary as NSString).length, breaks: [0, chapter])
        XCTAssertEqual(added, [NSRange(location: chapter, length: (text as NSString).length - chapter)])
    }

    func testTextWithoutSpacesIsCutAtLimit() {
        let segments = Narrator.voiceSegments(of: String(repeating: "a", count: 600))
        XCTAssertEqual(segments.first?.length, 250)
        XCTAssertEqual(covered(segments), 600)
    }

    private func date(_ day: Int, month: Int = 11) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    func testDailyAndMonthlyLimits() {
        let defaults = UserDefaults(suiteName: "CloudVoiceTests-\(UUID().uuidString)")!
        let allowance = VoiceAllowance(defaults: defaults)
        XCTAssertEqual(allowance.remaining(now: date(3)), 60_000)
        allowance.record(59_000, now: date(3))
        XCTAssertEqual(allowance.remaining(now: date(3)), 1_000)
        // Ertesi gün günlük sınır yenilenir.
        XCTAssertEqual(allowance.remaining(now: date(4)), 60_000)
        // Ay dolmaya yakınken aydan kalan geçerli.
        allowance.record(830_000, now: date(4))
        XCTAssertEqual(allowance.remaining(now: date(5)), 11_000)
        // Yeni ayda sıfırdan.
        XCTAssertEqual(allowance.remaining(now: date(1, month: 12)), 60_000)
    }

    @MainActor
    func testVoiceNamesAndCacheFiles() {
        XCTAssertEqual(CloudVoice.voice(for: "tr").name, "tr-TR-Chirp3-HD-Kore")
        XCTAssertEqual(CloudVoice.voice(for: "en").language, "en-US")
        let first = CloudVoice.cacheFile(text: "Merhaba.", voice: "tr-TR-Chirp3-HD-Kore")
        XCTAssertEqual(first, CloudVoice.cacheFile(text: "Merhaba.", voice: "tr-TR-Chirp3-HD-Kore"))
        XCTAssertNotEqual(first, CloudVoice.cacheFile(text: "Merhaba.", voice: "en-US-Chirp3-HD-Kore"))
        XCTAssertEqual(first.pathExtension, "mp3")
    }
}

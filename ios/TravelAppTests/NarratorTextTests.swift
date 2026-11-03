import XCTest
@testable import TravelApp

/// Ses, Latin dışı yazıları ve okunuş işaretlerini hece hece okumasın.
final class NarratorTextTests: XCTestCase {
    func testDropsForeignScriptAndPronunciation() {
        XCTAssertEqual(Narrator.speakable("Kız Kulesi (Yunanca: Δαμάλεις), Üsküdar'dadır."),
                       "Kız Kulesi, Üsküdar'dadır.")
        XCTAssertEqual(Narrator.speakable("Meiji Jingū (明治神宮) Tokyo'dadır."), "Meiji Jingū Tokyo'dadır.")
        XCTAssertEqual(Narrator.speakable("Tokyo (/ˈtoʊkioʊ/) büyük bir şehirdir.[3]"), "Tokyo büyük bir şehirdir.")
    }

    func testKeepsTurkishAndDates() {
        let text = "Ayasofya (532-537) Bizans döneminde yapıldı (İstanbul, Fatih)."
        XCTAssertEqual(Narrator.speakable(text), text)
    }
}

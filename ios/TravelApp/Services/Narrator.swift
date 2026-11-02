import AVFoundation

/// Anlatımları iPhone'un kendi sesiyle okur (ücretsiz, internetsiz).
/// Yeni anlatım başlarken öncekini durdurur; anlatımlar üst üste binmez.
/// Ekranın altındaki çubuktan duraklatılır, 10 sn geri ya da ileri ya da
/// çizgiden istenen yere sarılır. Uzun yazılar bölüm bölüm okunur
/// (Hakkında, Tarihçe, Mimari...): bir bölüme atlanır, bölüm atlanabilir;
/// hız 0,75x – 1,5x arası seçilir.
@MainActor
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    /// Anlatımın bir bölümü; `start` bölümün yazıdaki başlangıcı.
    struct Chapter: Equatable, Identifiable {
        var heading: String
        var start: Int
        var length: Int
        var id: Int { start }
    }

    @Published private(set) var currentTitle: String?
    @Published private(set) var isPaused = false
    /// Okunan yer, metnin başından sonuna (0...1).
    @Published private(set) var progress: Double = 0
    @Published private(set) var chapters: [Chapter] = []
    /// Okunan bölüm (`chapters` içinde).
    @Published private(set) var chapterIndex = 0
    /// Kullanıcının atladığı bölümler (okunmaz, sıra gelince geçilir).
    @Published private(set) var skippedChapters: Set<Int> = []
    /// Okuma hızı (1 = normal). Ayar telefonda saklanır.
    @Published private(set) var rate: Double

    static let rates: [Double] = [0.75, 1, 1.25, 1.5]
    private static let rateKey = "narrationRate"

    private let synthesizer = AVSpeechSynthesizer()
    private var text: NSString = ""
    private var language = "tr"
    /// Şu anki cümlenin metinde başladığı yer (sarınca metnin ortasından başlar).
    private var offset = 0
    /// Okunan kelimenin metindeki yeri.
    private var position = 0
    private var utteranceID: ObjectIdentifier?
    /// Duraklatılmışken hız değişti: devam edince yeni hızla baştan kurulur.
    private var restartsOnResume = false
    /// Çalan sesin okuduğu yazının sonu; sonradan eklenen bölümler
    /// (yazının devamı) bu sesin bitiminde okunur.
    private var utteranceEnd = 0

    /// iPhone sesinin saniyede okuduğu yaklaşık harf (normal hızda).
    private static let charactersPerSecond = 14.0

    override init() {
        let stored = UserDefaults.standard.double(forKey: Self.rateKey)
        rate = Self.rates.contains(stored) ? stored : 1
        super.init()
        synthesizer.delegate = self
    }

    var isActive: Bool { currentTitle != nil }
    var isSpeaking: Bool { synthesizer.isSpeaking && !synthesizer.isPaused }

    private var charactersPerSecond: Double { Self.charactersPerSecond * rate }

    /// Çalan anlatımın yaklaşık süresi ve geçen süre (saniye).
    var duration: Double { Double(text.length) / charactersPerSecond }
    var elapsed: Double { progress * duration }

    /// Bir yazının okunması yaklaşık kaç saniye sürer (seçili hızda).
    static func estimatedDuration(of text: String) -> Double {
        Double((text as NSString).length) / (charactersPerSecond * shared.rate)
    }

    /// Bir bölümün yaklaşık süresi (saniye, seçili hızda).
    func duration(of chapter: Chapter) -> Double {
        Double(chapter.length) / charactersPerSecond
    }

    /// "1:05" gibi dakika:saniye.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "1x", "1,25x" gibi.
    static func rateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "x"
    }

    func speak(_ text: String, title: String, language: String) {
        speak(sections: [(heading: "", text: text)], title: title, language: language)
    }

    /// Özet ve yazının bölümleri art arda; her bölüm bir çip. İlk bölümün
    /// başlığı okunmaz ("Hakkında"), sonrakilerin başlığı okunur.
    func speak(summary: WikipediaService.Summary, article: WikipediaService.Article?, title: String) {
        var sections = [(heading: String(localized: "Hakkında"), text: summary.extract)]
        if let article, article.language == summary.language {
            sections += article.sections.map { (heading: $0.heading, text: $0.text) }
        }
        speak(sections: sections, title: title, language: summary.language)
    }

    func speak(sections: [(heading: String, text: String)], title: String, language: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        var full = ""
        var found: [Chapter] = []
        for (index, section) in sections.enumerated() where !section.text.isEmpty {
            if !full.isEmpty { full += "\n\n" }
            let start = (full as NSString).length
            let spoken = index == 0 || section.heading.isEmpty ? section.text : "\(section.heading).\n\(section.text)"
            full += spoken
            found.append(Chapter(heading: section.heading, start: start, length: (spoken as NSString).length))
        }
        text = full as NSString
        self.language = language
        chapters = found.count > 1 ? found : []
        skippedChapters = []
        chapterIndex = 0
        currentTitle = title
        play(from: 0)
    }

    /// Çalan anlatıma yazının devamını (bölümler) ekler: özet okunurken
    /// sayfanın tamamı gelince çipler belirir, özet bitince devamı okunur.
    func append(sections: [(heading: String, text: String)], to title: String) {
        guard currentTitle == title else { return }
        let sections = sections.filter { !$0.text.isEmpty }
        guard !sections.isEmpty else { return }
        var full = text as String
        var found = chapters
        if found.isEmpty {
            found = [Chapter(heading: String(localized: "Hakkında"), start: 0, length: text.length)]
        }
        for section in sections {
            full += "\n\n"
            let start = (full as NSString).length
            let spoken = "\(section.heading).\n\(section.text)"
            full += spoken
            found.append(Chapter(heading: section.heading, start: start, length: (spoken as NSString).length))
        }
        text = full as NSString
        chapters = found
        update(position: position)
    }

    /// Yazının bölümleri eklenmiş mi (özetten fazlası okunuyor mu)?
    var hasChapters: Bool { !chapters.isEmpty }

    func togglePause() {
        if restartsOnResume, isActive {
            restartsOnResume = false
            play(from: wordStart(atOrBefore: position))
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        } else if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    /// Kabaca `seconds` saniye ileri (artı) ya da geri (eksi) sarar; kelime başından devam eder.
    func skip(by seconds: Double) {
        guard isActive else { return }
        let target = position + Int(seconds * charactersPerSecond)
        guard target < text.length - 1 else {
            stop()
            return
        }
        play(from: wordStart(atOrBefore: max(target, 0)))
    }

    /// Çizginin bir yerine dokununca oradan (kelime başından) devam eder.
    func seek(to fraction: Double) {
        guard isActive, text.length > 1 else { return }
        let target = Int(Double(text.length) * min(max(fraction, 0), 1))
        guard target < text.length - 1 else {
            stop()
            return
        }
        play(from: wordStart(atOrBefore: target))
    }

    /// Bölümün başından okur (atlanmışsa yeniden ekler).
    func play(chapter index: Int) {
        guard isActive, chapters.indices.contains(index) else { return }
        skippedChapters.remove(index)
        play(from: chapters[index].start)
    }

    /// Bölümü atlar ya da geri ekler. Okunan bölüm atlanınca sıradakine geçer.
    func toggleSkip(chapter index: Int) {
        guard chapters.indices.contains(index) else { return }
        if skippedChapters.contains(index) {
            skippedChapters.remove(index)
            return
        }
        skippedChapters.insert(index)
        if index == chapterIndex, isActive { continueAfterSkipped(from: index) }
    }

    func setRate(_ rate: Double) {
        guard Self.rates.contains(rate), rate != self.rate else { return }
        self.rate = rate
        UserDefaults.standard.set(rate, forKey: Self.rateKey)
        // Çalıyorsa yeni hızla aynı kelimeden devam eder.
        if isPaused {
            restartsOnResume = true
        } else if isActive {
            play(from: wordStart(atOrBefore: position))
        }
    }

    func stop() {
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        currentTitle = nil
        isPaused = false
        progress = 0
        position = 0
        chapterIndex = 0
    }

    private func play(from start: Int) {
        restartsOnResume = false
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        offset = start
        update(position: start)
        utteranceEnd = text.length
        let utterance = AVSpeechUtterance(string: text.substring(from: start))
        utterance.voice = Self.voice(for: language)
        utterance.rate = Self.utteranceRate(rate)
        utteranceID = ObjectIdentifier(utterance)
        isPaused = false
        synthesizer.speak(utterance)
    }

    private func update(position: Int) {
        self.position = position
        progress = text.length > 0 ? Double(position) / Double(text.length) : 0
        let index = chapters.lastIndex { $0.start <= position } ?? 0
        if index != chapterIndex { chapterIndex = index }
    }

    /// Atlanan bölümden sonraki ilk atlanmamış bölüme geçer; yoksa biter.
    private func continueAfterSkipped(from index: Int) {
        if let next = chapters.indices.first(where: { $0 > index && !skippedChapters.contains($0) }) {
            play(from: chapters[next].start)
        } else {
            stop()
        }
    }

    /// iPhone sesinin hızı: 0,5 normal; yavaşlatma ve hızlandırma eşit
    /// algılansın diye iki yanda farklı adım (Tokyo testinde ayarlanacak).
    private static func utteranceRate(_ rate: Double) -> Float {
        let base = AVSpeechUtteranceDefaultSpeechRate
        let value = rate >= 1 ? base + Float(rate - 1) * 0.2 : base - Float(1 - rate) * 0.4
        return min(max(value, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func wordStart(atOrBefore index: Int) -> Int {
        var index = min(index, text.length - 1)
        while index > 0, let scalar = UnicodeScalar(text.character(at: index - 1)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            index -= 1
        }
        return max(index, 0)
    }

    /// Dilin en iyi iPhone sesi (indirilmiş "gelişmiş" ses varsa o).
    private static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let code = language == "tr" ? "tr-TR" : "en-US"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == code && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: code)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.utteranceID else { return }
            self.update(position: self.offset + characterRange.location)
            // Atlanan bölüme gelindi: sıradakine geç.
            if self.skippedChapters.contains(self.chapterIndex) {
                self.continueAfterSkipped(from: self.chapterIndex)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.utteranceID else { return }
            // Bu ses başladıktan sonra yazının devamı eklendiyse onu oku.
            if self.utteranceEnd < self.text.length {
                self.play(from: self.utteranceEnd)
                if self.skippedChapters.contains(self.chapterIndex) { self.continueAfterSkipped(from: self.chapterIndex) }
                return
            }
            self.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

import AVFoundation

/// Anlatımları Google'ın doğal sesiyle (Chirp 3 HD, `CloudVoice`) okur;
/// olmazsa (sınır, internet yok, anahtar yok) iPhone'un kendi sesiyle.
/// Google sesinde yazı parça parça (cümle sonlarından) sese çevrilir: ilk
/// parça kısa olduğu için okuma hemen başlar, sonraki parçalar okunurken
/// hazırlanır. Yeni anlatım başlarken öncekini durdurur; anlatımlar üst üste binmez.
/// Ekranın altındaki çubuktan duraklatılır, 10 sn geri ya da ileri ya da
/// çizgiden istenen yere sarılır. Uzun yazılar bölüm bölüm okunur
/// (Hakkında, Tarihçe, Mimari...): bir bölüme atlanır, bölüm atlanabilir;
/// hız 0,75x – 1,5x arası seçilir.
@MainActor
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
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

    // Google sesi
    /// Bu anlatım Google sesiyle mi okunuyor.
    private var usesCloud = false
    /// Yazının sese çevrilen parçaları (yazıdaki yerleri).
    private var segments: [NSRange] = []
    private var segmentIndex = 0
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    /// Her parça başlatılışı yeni bir kimlik alır; geç gelen eski ses çalınmaz.
    private var playback = UUID()

    override init() {
        let stored = UserDefaults.standard.double(forKey: Self.rateKey)
        rate = Self.rates.contains(stored) ? stored : 1
        super.init()
        synthesizer.delegate = self
    }

    var isActive: Bool { currentTitle != nil }
    var isSpeaking: Bool {
        usesCloud ? isActive && !isPaused : synthesizer.isSpeaking && !synthesizer.isPaused
    }

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
            let body = Self.speakable(section.text)
            let spoken = index == 0 || section.heading.isEmpty ? body : "\(section.heading).\n\(body)"
            full += spoken
            found.append(Chapter(heading: section.heading, start: start, length: (spoken as NSString).length))
        }
        text = full as NSString
        self.language = language
        chapters = found.count > 1 ? found : []
        skippedChapters = []
        chapterIndex = 0
        currentTitle = title
        usesCloud = CloudVoice.shared.isAvailable
        segments = usesCloud ? Self.voiceSegments(of: full, breaks: found.map(\.start)) : []
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
            let spoken = "\(section.heading).\n\(Self.speakable(section.text))"
            full += spoken
            found.append(Chapter(heading: section.heading, start: start, length: (spoken as NSString).length))
        }
        let previousEnd = text.length
        text = full as NSString
        chapters = found
        if usesCloud {
            segments += Self.voiceSegments(of: full, from: previousEnd, breaks: found.map(\.start))
        }
        update(position: position)
    }

    /// Yazının bölümleri eklenmiş mi (özetten fazlası okunuyor mu)?
    var hasChapters: Bool { !chapters.isEmpty }

    func togglePause() {
        if usesCloud {
            guard isActive else { return }
            isPaused.toggle()
            // Ses daha gelmediyse gelince (duraklatılmadıysa) çalar.
            if isPaused { player?.pause() } else { player?.play() }
            return
        }
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
        if usesCloud, let player {
            let time = player.currentTime + seconds
            if time >= 0, time < player.duration {
                player.currentTime = time
                tick()
                return
            }
        }
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
        // Google sesinde aynı parçanın içindeyse yalnızca ses sarılır.
        if usesCloud, let player, segments.indices.contains(segmentIndex),
           NSLocationInRange(target, segments[segmentIndex]) {
            let segment = segments[segmentIndex]
            player.currentTime = player.duration * Double(target - segment.location) / Double(max(segment.length, 1))
            tick()
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
        if usesCloud {
            player?.rate = Float(rate)
            return
        }
        // Çalıyorsa yeni hızla aynı kelimeden devam eder.
        if isPaused {
            restartsOnResume = true
        } else if isActive {
            play(from: wordStart(atOrBefore: position))
        }
    }

    func stop() {
        stopCloud()
        usesCloud = false
        segments = []
        segmentIndex = 0
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        currentTitle = nil
        isPaused = false
        progress = 0
        position = 0
        chapterIndex = 0
    }

    private func play(from start: Int) {
        if usesCloud {
            playCloud(from: start)
            return
        }
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

    // MARK: - Google sesi

    /// Yazının `start`'ı içeren parçasını sese çevirip o noktadan çalar.
    private func playCloud(from start: Int) {
        stopCloud()
        guard let index = segments.firstIndex(where: { $0.location + $0.length > start }) else {
            stop()
            return
        }
        let segment = segments[index]
        let begin = max(start, segment.location)
        segmentIndex = index
        isPaused = false
        update(position: begin)
        let id = playback
        let piece = text.substring(with: segment)
        let language = self.language
        Task {
            let file = await CloudVoice.shared.audioFile(for: piece, language: language)
            guard id == self.playback, self.isActive else { return }
            guard let file, let player = try? AVAudioPlayer(contentsOf: file), player.duration > 0 else {
                // Google sesi alınamadı: anlatım buradan iPhone sesiyle sürer.
                self.usesCloud = false
                self.play(from: begin)
                return
            }
            player.delegate = self
            player.enableRate = true
            player.rate = Float(self.rate)
            player.currentTime = player.duration * Double(begin - segment.location) / Double(max(segment.length, 1))
            self.player = player
            if self.isPaused { player.prepareToPlay() } else { player.play() }
            self.startTicker()
            self.prefetch(after: index)
        }
    }

    /// Sıradaki iki parça okunan parça çalarken hazırlanır (atlanan bölümler hariç).
    private func prefetch(after index: Int) {
        let language = self.language
        for segment in segments.dropFirst(index + 1).prefix(2) {
            let chapter = chapters.lastIndex { $0.start <= segment.location } ?? 0
            guard !skippedChapters.contains(chapter) else { continue }
            let piece = text.substring(with: segment)
            Task { _ = await CloudVoice.shared.audioFile(for: piece, language: language) }
        }
    }

    private func stopCloud() {
        playback = UUID()
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Liste kaydırılırken de ilerlesin.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Çalan sesin yeri yazıdaki yere çevrilir (çizgi, bölüm çipi).
    private func tick() {
        guard usesCloud, let player, segments.indices.contains(segmentIndex) else { return }
        let segment = segments[segmentIndex]
        let fraction = player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
        update(position: segment.location + Int(Double(segment.length) * fraction))
        if skippedChapters.contains(chapterIndex) { continueAfterSkipped(from: chapterIndex) }
    }

    private func nextSegment() {
        let next = segmentIndex + 1
        guard segments.indices.contains(next) else {
            stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        playCloud(from: segments[next].location)
        if skippedChapters.contains(chapterIndex) { continueAfterSkipped(from: chapterIndex) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == id else { return }
            self.nextSegment()
        }
    }

    /// Yazıyı Google sesine gidecek parçalara böler: cümle sonlarından,
    /// bölüm başlarından. İlk parça kısa (okuma hemen başlasın), bölümlerin
    /// ilk parçası orta (bölüme atlayınca çabuk başlasın), gerisi uzun.
    /// Yalnızca boşluk olan parçalar atlanır.
    nonisolated static func voiceSegments(of text: String, from start: Int = 0, breaks: [Int] = [],
                                     first: Int = 250, chapterFirst: Int = 450, length: Int = 1500) -> [NSRange] {
        let source = text as NSString
        var result: [NSRange] = []
        var location = max(start, 0)
        while location < source.length {
            let limit = location == 0 ? first : breaks.contains(location) ? chapterFirst : length
            var end = min(location + limit, source.length)
            if let chapter = breaks.first(where: { $0 > location && $0 < end }) {
                end = chapter
            } else if end < source.length {
                end = breakPoint(in: source, from: location, to: end)
            }
            let range = NSRange(location: location, length: end - location)
            if !source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(range)
            }
            location = end
        }
        return result
    }

    /// `end`'den geriye en yakın cümle sonu (ya da satır sonu); yoksa
    /// boşluk; o da yoksa `end`. Parçanın ilk üçte birine inilmez.
    nonisolated private static func breakPoint(in text: NSString, from location: Int, to end: Int) -> Int {
        let minimum = location + (end - location) / 3
        func isSpace(_ unit: unichar) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 0xA0 }
        func isSentenceEnd(_ unit: unichar) -> Bool { [46, 33, 63, 0x2026].contains(unit) }
        var index = end
        while index > minimum {
            let previous = text.character(at: index - 1)
            if previous == 10 { return index }
            if isSpace(previous), index - 2 >= location, isSentenceEnd(text.character(at: index - 2)) { return index }
            index -= 1
        }
        index = end
        while index > minimum {
            if isSpace(text.character(at: index - 1)) { return index }
            index -= 1
        }
        return end
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

    /// Sesin takıldığı parçalar okunmaz: içinde Latin dışı yazı (Japonca,
    /// Yunanca, Arapça...) ya da okunuş işaretleri olan parantezler
    /// ("(Yunanca: Δαμάλεις)", "(/ˈtoʊkioʊ/)") ve kaynak numaraları ("[3]").
    /// Yazının ekrandaki hâli değişmez.
    nonisolated static func speakable(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\\[[0-9a-z ]{1,5}\\]", with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "\\s*\\(([^()]*)\\)") else { return cleaned }
        let source = cleaned as NSString
        var output = ""
        var last = 0
        for match in regex.matches(in: cleaned, range: NSRange(location: 0, length: source.length))
        where isUnspeakable(source.substring(with: match.range(at: 1))) {
            output += source.substring(with: NSRange(location: last, length: match.range.location - last))
            last = match.range.location + match.range.length
        }
        output += source.substring(from: last)
        return output.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
    }

    /// Latin harfleri (Türkçe dahil) dışında bir yazı ya da IPA işareti var mı.
    nonisolated private static func isUnspeakable(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            if (0x0250...0x02FF).contains(value) { return true }
            guard scalar.properties.isAlphabetic else { return false }
            return !(value < 0x0250 || (0x1E00...0x1EFF).contains(value))
        }
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

/// Bir yerin anlatımı, yer penceresindeki "Dinle" ile aynı içerik: Wikipedia
/// özeti hemen okunmaya başlar, yazının bütün bölümleri (Tarihçe, Mimari...)
/// gelince arkasına eklenir. Yerin sayfası bilinmiyorsa önce aranır
/// (aramayla eklenen yerler). Wikipedia yazısı yoksa Wikivoyage'daki
/// gezgin notu, o da yoksa adı ve türü okunur.
@MainActor
enum PlaceNarration {
    /// `ready`: okuma başlamadan hemen önce (yükleniyor göstergesi kalksın).
    static func play(_ place: Place, store: AppStore, ready: () -> Void = {}) async {
        let narrator = Narrator.shared
        let title = await store.wikipediaTitle(for: place)
        var found: WikipediaService.Summary?
        if let title { found = await WikipediaService.shared.summary(englishTitle: title) }
        guard let title, let summary = found else {
            let listing = await WikivoyageListings.shared.listing(name: place.name, latitude: place.latitude,
                                                                  longitude: place.longitude)
            ready()
            guard !Task.isCancelled else { return }
            if let listing {
                narrator.speak(summary: listing.summary, article: nil, title: place.name)
            } else {
                narrator.speak(String(localized: "\(place.name). \(place.category.title)."), title: place.name,
                               language: WikipediaService.narrationLanguage)
            }
            return
        }
        ready()
        guard !Task.isCancelled else { return }
        narrator.speak(summary: summary, article: nil, title: place.name)
        guard let article = await WikipediaService.shared.article(englishTitle: title),
              !Task.isCancelled, article.language == summary.language else { return }
        narrator.append(sections: article.sections.map { (heading: $0.heading, text: $0.text) }, to: place.name)
    }
}

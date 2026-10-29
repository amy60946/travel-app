import AVFoundation

/// Anlatımları iPhone'un kendi sesiyle okur (ücretsiz, internetsiz).
/// Yeni anlatım başlarken öncekini durdurur; anlatımlar üst üste binmez.
/// Ekranın altındaki çubuktan duraklatılır, 10 sn geri ya da ileri sarılır.
@MainActor
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    @Published private(set) var currentTitle: String?
    @Published private(set) var isPaused = false
    /// Okunan yer, metnin başından sonuna (0...1).
    @Published private(set) var progress: Double = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var text: NSString = ""
    private var language = "tr"
    /// Şu anki cümlenin metinde başladığı yer (sarınca metnin ortasından başlar).
    private var offset = 0
    /// Okunan kelimenin metindeki yeri.
    private var position = 0
    private var utteranceID: ObjectIdentifier?

    /// iPhone sesinin saniyede okuduğu yaklaşık harf (normal hızda).
    private static let charactersPerSecond = 14.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isActive: Bool { currentTitle != nil }
    var isSpeaking: Bool { synthesizer.isSpeaking && !synthesizer.isPaused }

    func speak(_ text: String, title: String, language: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        self.text = text as NSString
        self.language = language
        currentTitle = title
        play(from: 0)
    }

    func togglePause() {
        if synthesizer.isPaused {
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
        let target = position + Int(seconds * Self.charactersPerSecond)
        guard target < text.length - 1 else {
            stop()
            return
        }
        play(from: wordStart(atOrBefore: max(target, 0)))
    }

    func stop() {
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        currentTitle = nil
        isPaused = false
        progress = 0
        position = 0
    }

    private func play(from start: Int) {
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        offset = start
        position = start
        progress = text.length > 0 ? Double(start) / Double(text.length) : 0
        let utterance = AVSpeechUtterance(string: text.substring(from: start))
        utterance.voice = Self.voice(for: language)
        utteranceID = ObjectIdentifier(utterance)
        isPaused = false
        synthesizer.speak(utterance)
    }

    private func wordStart(atOrBefore index: Int) -> Int {
        var index = min(index, text.length - 1)
        while index > 0, let scalar = UnicodeScalar(text.character(at: index - 1)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            index -= 1
        }
        return index
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
            self.position = self.offset + characterRange.location
            self.progress = self.text.length > 0 ? Double(self.position) / Double(self.text.length) : 0
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.utteranceID else { return }
            self.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

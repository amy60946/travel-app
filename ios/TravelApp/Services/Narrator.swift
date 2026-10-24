import AVFoundation

/// Anlatımları iPhone'un kendi sesiyle okur (ücretsiz, internetsiz).
/// Yeni anlatım başlarken öncekini durdurur; anlatımlar üst üste binmez.
@MainActor
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    @Published private(set) var currentTitle: String?
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isActive: Bool { currentTitle != nil }

    func speak(_ text: String, title: String, language: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language == "tr" ? "tr-TR" : "en-US")
        currentTitle = title
        isPaused = false
        synthesizer.speak(utterance)
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

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentTitle = nil
        isPaused = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentTitle = nil
            self.isPaused = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

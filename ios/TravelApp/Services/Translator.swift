import SwiftUI
import Translation

/// İngilizce metni Türkçeye çevirir (Türkçe kaynağı olmayan anlatımlar
/// için). iPhone'da Türkçe çeviri paketi zaten iniyse iPhone'un kendi
/// çevirisi (ücretsiz, iOS 18 ve sonrası), değilse Gemini / Groq ücretsiz
/// katmanı. Paket inmemişken iPhone çevirisi indirme penceresi açıyordu; o
/// pencere yer penceresinin arkasında kalıp yazıyı bekletiyordu, bu yüzden
/// indirme hiç sorulmaz. İkisi de olmazsa nil.
@MainActor
final class Translator: ObservableObject {
    static let shared = Translator()

    /// Bekleyen çeviri sayısı; değişince uygulamanın kökündeki çeviri işi çalışır.
    @Published private(set) var pendingCount = 0

    private struct Request {
        let id = UUID()
        let text: String
        let done: CheckedContinuation<String?, Never>
    }

    private var pending: [Request] = []
    /// Uygulamanın kökünde iPhone çevirisi hazır mı (iOS 18+).
    fileprivate var hostAttached = false
    fileprivate var isDraining = false

    func toTurkish(_ text: String) async -> String? {
        if hostAttached, await turkishIsInstalled(), let translated = await systemTranslation(text) {
            return translated
        }
        return await PlaceAI.translateToTurkish(text)
    }

    /// iPhone'un İngilizce → Türkçe çeviri paketi telefonda hazır mı?
    private func turkishIsInstalled() async -> Bool {
        guard #available(iOS 18.0, *) else { return false }
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"),
                                                         to: Locale.Language(identifier: "tr"))
        return status == .installed
    }

    private func systemTranslation(_ text: String) async -> String? {
        await withCheckedContinuation { continuation in
            let request = Request(text: text, done: continuation)
            pending.append(request)
            pendingCount = pending.count
            // Çeviri hiç başlamazsa beklemede kalmasın.
            Task {
                try? await Task.sleep(for: .seconds(10))
                self.finish(request.id, with: nil)
            }
        }
    }

    private func finish(_ id: UUID, with result: String?) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        pendingCount = pending.count
        request.done.resume(returning: result)
    }

    @available(iOS 18.0, *)
    fileprivate func drain(using session: TranslationSession) async {
        isDraining = true
        defer { isDraining = false }
        while let request = pending.first {
            let response = try? await session.translate(request.text)
            finish(request.id, with: response?.targetText)
        }
    }
}

/// iPhone çevirisini uygulamanın köküne bağlar (bir kez, RootView'da).
@available(iOS 18.0, *)
private struct TranslationHost: ViewModifier {
    @ObservedObject private var translator = Translator.shared
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await translator.drain(using: session)
            }
            .onAppear { translator.hostAttached = true }
            .onChange(of: translator.pendingCount) { _, count in
                guard count > 0, !translator.isDraining else { return }
                if configuration == nil {
                    configuration = .init(source: Locale.Language(identifier: "en"),
                                          target: Locale.Language(identifier: "tr"))
                } else {
                    configuration?.invalidate()
                }
            }
    }
}

extension View {
    @ViewBuilder
    func translationHost() -> some View {
        if #available(iOS 18.0, *) {
            modifier(TranslationHost())
        } else {
            self
        }
    }
}

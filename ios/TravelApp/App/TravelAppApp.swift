import SwiftUI

@main
struct TravelAppApp: App {
    @StateObject private var store = AppStore(fileURL: TravelAppApp.launchScreenStateURL)
    /// Ayarlar'dan seçilen dil (varsayılan Türkçe); değişince bütün ekranlar
    /// o dilde yeniden çizilir.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.turkish.rawValue

    init() {
        AppLanguage.activate()
        GoogleAPI.configure()
    }

    /// Yalnızca geliştirme sürümünde: ekran görüntüsü açılışları (`-screen`)
    /// her seferinde örnek verilerle başlasın, birinin değişikliği ötekine
    /// geçmesin.
    private static var launchScreenStateURL: URL? {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "screen") != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("state.json")
        }
        #endif
        return nil
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(language)
                .environment(\.locale, AppLanguage.current.locale)
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Theme.ink)
        }
    }
}

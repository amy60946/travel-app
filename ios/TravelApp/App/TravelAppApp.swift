import SwiftUI

@main
struct TravelAppApp: App {
    @StateObject private var store = AppStore(fileURL: TravelAppApp.launchScreenStateURL)

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
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Theme.ink)
        }
    }
}

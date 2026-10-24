import SwiftUI

@main
struct TravelAppApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}

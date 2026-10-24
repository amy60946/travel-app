import SwiftUI

enum Route: Hashable {
    case city(String)
    case place(UUID)
    case walk(city: String, day: Int)
}

enum RootTab: Hashable {
    case explore, saved, downloads
}

/// Alt çubuk (beyaz hap) + siyah "+" ve sekmeler.
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var path: [Route] = []
    @State private var tab: RootTab = .explore
    @State private var sheet: AddSheet?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .explore: HomeView(path: $path)
                    case .saved: SavedPlacesView(path: $path)
                    case .downloads: DownloadsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    UndoToast()
                    TabBar(tab: $tab, onAdd: { sheet = .addPlace(city: store.cities.first?.name ?? "Tokyo") })
                }
                .padding(.bottom, 8)
                .animation(.snappy, value: store.undoMessage)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .city(let name): CityPlanView(city: name, path: $path)
                case .place(let id): PlaceDetailView(placeID: id)
                case .walk(let city, let day): WalkView(city: city, dayIndex: day)
                }
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .sheet(item: $sheet) { sheet in
            sheet.view
        }
    }
}

/// Uygulama genelinde açılan alt pencereler.
enum AddSheet: Identifiable {
    case addPlace(city: String)
    case customPlace(city: String)

    var id: String {
        switch self {
        case .addPlace(let city): "add-\(city)"
        case .customPlace(let city): "custom-\(city)"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .addPlace(let city): AddPlaceView(city: city)
        case .customPlace(let city): CustomPlaceView(city: city)
        }
    }
}

private struct TabBar: View {
    @Binding var tab: RootTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                item(.explore, "Keşfet", "globe.europe.africa")
                item(.saved, "Kayıtlar", "bookmark")
                item(.downloads, "İndirilenler", "arrow.down.circle")
            }
            .padding(6)
            .background(.white, in: Capsule())
            .softShadow()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.ink, in: Circle())
                    .softShadow()
            }
            .accessibilityLabel(Text("Ekle"))
        }
    }

    private func item(_ value: RootTab, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button {
            tab = value
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(Theme.font(11, .semibold))
            }
            .foregroundStyle(tab == value ? Theme.ink : Theme.muted)
            .frame(width: 82, height: 44)
            .background(tab == value ? Theme.surface : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

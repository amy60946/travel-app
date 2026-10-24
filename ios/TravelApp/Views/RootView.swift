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
                    TabBar(tab: $tab, city: store.cities.first?.name ?? "Tokyo", sheet: $sheet)
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
        .task { openLaunchScreen() }
    }

    /// Yalnızca geliştirme sürümünde: `-screen city` gibi bir açılış
    /// argümanıyla istenen ekranı açar (derlemedeki ekran görüntüleri için).
    private func openLaunchScreen() {
        #if DEBUG
        guard let screen = UserDefaults.standard.string(forKey: "screen") else { return }
        let city = store.cities.first?.name ?? "Tokyo"
        let firstPlace = store.places(in: city).first
        switch screen {
        case "saved": tab = .saved
        case "downloads": tab = .downloads
        case "city": path = [.city(city)]
        case "place": if let firstPlace { path = [.city(city), .place(firstPlace.id)] }
        case "walk": path = [.city(city), .walk(city: city, day: 0)]
        case "add": sheet = .addPlace(city: city)
        case "import": sheet = .importData
        case "camera": sheet = .camera
        case "custom": sheet = .customPlace(city: city)
        default: break
        }
        #endif
    }
}

/// Uygulama genelinde açılan alt pencereler.
enum AddSheet: Identifiable {
    case addPlace(city: String)
    case customPlace(city: String)
    case importData
    case camera

    var id: String {
        switch self {
        case .addPlace(let city): "add-\(city)"
        case .customPlace(let city): "custom-\(city)"
        case .importData: "import"
        case .camera: "camera"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .addPlace(let city): AddPlaceView(city: city)
        case .customPlace(let city): CustomPlaceView(city: city)
        case .importData: ImportView()
        case .camera: CameraAddView()
        }
    }
}

private struct TabBar: View {
    @Binding var tab: RootTab
    let city: String
    @Binding var sheet: AddSheet?

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

            Menu {
                Button { sheet = .addPlace(city: city) } label: { Label("Yer ekle", systemImage: "magnifyingglass") }
                Button { sheet = .camera } label: { Label("Fotoğrafla ekle", systemImage: "camera") }
                Button { sheet = .importData } label: { Label("Veri dosyası ya da link aktar", systemImage: "square.and.arrow.down") }
                Button { sheet = .customPlace(city: city) } label: { Label("Kendi yerini oluştur", systemImage: "mappin.and.ellipse") }
            } label: {
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

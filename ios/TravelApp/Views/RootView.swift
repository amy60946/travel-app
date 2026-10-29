import SwiftUI

enum Route: Hashable {
    case city(String)
    case place(UUID)
    case walk(city: String, day: Int)
}

enum RootTab: Hashable {
    case explore, saved, downloads
}

/// Alt çubuk (beyaz hap) + siyah büyüteç ("Yer ekle") ve sekmeler. Anlatım
/// çalarken en altta oynatıcı çubuğu durur; sayfa değişse de görünür.
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var tab: RootTab = .explore
    @State private var sheet: AddSheet?
    /// Büyütecin "Yer ekle"yi açacağı şehir (ana haritada ortaya en yakın şehir).
    @State private var searchCity = ""
    @State private var guidance: GuidanceDestination?

    /// Yürüyüş ekranının kendi çalar düğmeleri var; orada çubuk gösterilmez.
    private var showsNarrationBar: Bool {
        if case .walk = path.last { return false }
        return true
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .explore: HomeView(path: $path, searchCity: $searchCity)
                    case .saved: SavedPlacesView(path: $path)
                    case .downloads: DownloadsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    UndoToast()
                    TabBar(tab: $tab, sheet: $sheet,
                           city: searchCity.isEmpty ? store.cities.first?.name ?? "Tokyo" : searchCity)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsNarrationBar { NarrationBar() }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .sheet(item: $sheet) { sheet in
            sheet.view
        }
        .fullScreenCover(item: $guidance) { GuidanceView(destination: $0) }
        // Türkçe kaynağı olmayan anlatımlar iPhone'un kendi çevirisiyle Türkçeye çevrilir.
        .translationHost()
        .task {
            openLaunchScreen()
            await openImportIfNewExport()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await openImportIfNewExport() } }
        }
        // Aktarılan yerlerin türünü (müze, kafe...) arka planda bulur;
        // yeni yer gelince kaldığı yerden devam eder.
        .task(id: store.places.count) { await store.refineCategories() }
        // E-postadan ya da Dosyalar'dan "Paylaş → TravelApp" ile gelen veri dosyası.
        .onOpenURL { url in
            if url.isFileURL { sheet = .importFile(url) }
        }
    }

    /// İndirilenler'e yeni bir Instagram/TikTok/Google dosyası indiyse
    /// aktarma ekranını açar; ekran dosyayı kendisi aktarır.
    private func openImportIfNewExport() async {
        guard sheet == nil, ImportView.openCount == 0, ExportFolder.isLinked else { return }
        let hasNew = await Task.detached { ExportFolder.hasNew() }.value
        if hasNew, sheet == nil, ImportView.openCount == 0 { sheet = .importData }
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
        case "city", "spot", "moved", "movedList", "photo", "sheetTall", "all": path = [.city(city)]
        case "player":
            path = [.city(city)]
            Narrator.shared.speak("Sensō-ji, Tokyo'nun Asakusa semtinde bulunan eski bir Budist tapınağıdır. "
                                  + "Tokyo'nun en eski tapınağıdır ve her yıl milyonlarca kişi ziyaret eder.",
                                  title: "Sensō-ji", language: "tr")
        case "guide":
            let places = store.places(in: city)
            if let target = places.first(where: { $0.name == "Tokyo Skytree" }) ?? places.first {
                guidance = GuidanceDestination(place: target)
            }
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
    case addPlace(city: String, day: Int = 0)
    case customPlace(city: String)
    case importData
    case importFile(URL)
    case camera

    var id: String {
        switch self {
        case .addPlace(let city, let day): "add-\(city)-\(day)"
        case .customPlace(let city): "custom-\(city)"
        case .importData: "import"
        case .importFile(let url): "import-\(url.lastPathComponent)"
        case .camera: "camera"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .addPlace(let city, let day): AddPlaceView(city: city, day: day)
        case .customPlace(let city): CustomPlaceView(city: city)
        case .importData: ImportView()
        case .importFile(let url): ImportView(initialFile: url)
        case .camera: CameraAddView()
        }
    }
}

private struct TabBar: View {
    @Binding var tab: RootTab
    @Binding var sheet: AddSheet?
    let city: String

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

            // Hızlı erişim: doğrudan "Yer ekle" (arama, kendi yerin, fotoğrafla ekle).
            Button { sheet = .addPlace(city: city) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.ink, in: Circle())
                    .softShadow()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Yer ara ve ekle"))
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

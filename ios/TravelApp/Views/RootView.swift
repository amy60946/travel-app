import CoreLocation
import SwiftUI

enum Route: Hashable {
    /// Gezideki bir şehrin planı (`Destination.id`).
    case plan(UUID)
    case place(UUID)
    case walk(stop: UUID, day: Int)
    case journey(UUID)
    case continent(String)
    case country(String)
    case cityGuide(CityChoice)
    case collection(UUID)
    /// Profil → Tüm kayıtlarım.
    case saved
    /// Profil → İndirilenler.
    case downloads
}

enum RootTab: Hashable {
    case map, discover, profile
}

/// Alt çubuk (beyaz hap) + siyah büyüteç (genel arama) ve sekmeler: Harita
/// (Gezilerim | Koleksiyonlar), Keşfet (kıta, ülke, şehir), Profil (bütün
/// kayıtlar, indirilenler, veri aktarma, dil ve harita ayarları). Anlatım
/// çalarken en altta oynatıcı çubuğu durur; sayfa değişse de görünür.
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    /// Dil değişince bütün ekranlar baştan kurulur; açık sekme kalsın.
    @State private var tab: RootTab = RootView.lastTab
    private static var lastTab: RootTab = .map
    @State private var sheet: AddSheet?
    /// Büyütecin "Yer ekle"yi açacağı şehir (ana haritada ortaya en yakın şehir).
    @State private var searchCity = ""
    @State private var guidance: GuidanceDestination?
    @State private var locationManager = CLLocationManager()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .map: HomeView(path: $path, searchCity: $searchCity, sheet: $sheet)
                    case .discover: DiscoverView(path: $path)
                    case .profile: ProfileView(path: $path, sheet: $sheet)
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
            .narrationBarInset()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .plan(let stopID): CityPlanView(stopID: stopID, path: $path).narrationBarInset()
                case .place(let id): PlaceDetailView(placeID: id).narrationBarInset(hiding: store.place(id)?.name)
                // Yürüyüş ekranının kendi çalar düğmeleri var; orada çubuk yok.
                case .walk(let stopID, let day): WalkView(stopID: stopID, dayIndex: day)
                case .journey(let id): JourneyView(journeyID: id, path: $path).narrationBarInset()
                case .continent(let id):
                    if let continent = Continent.find(id) {
                        ContinentView(continent: continent, path: $path).narrationBarInset()
                    }
                case .country(let code):
                    if let country = Country.find(code) {
                        CountryView(country: country, mode: .discover(open: { path.append(.cityGuide($0)) }))
                            .narrationBarInset()
                    }
                case .cityGuide(let city): CityGuideView(city: city, path: $path).narrationBarInset(hiding: city.name)
                case .collection(let id): CollectionDetailView(collectionID: id, path: $path).narrationBarInset()
                case .saved: SavedPlacesView(path: $path).narrationBarInset()
                case .downloads: DownloadsView().narrationBarInset()
                }
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .sheet(item: $sheet) { sheet in
            if case .newTrip = sheet {
                // Gezi oluşunca planı açılır.
                NewTripView(mode: .new) { id in
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(.journey(id))
                    }
                }
            } else {
                sheet.view
            }
        }
        .fullScreenCover(item: $guidance) { GuidanceView(destination: $0) }
        .onChange(of: tab) { _, tab in Self.lastTab = tab }
        // Türkçe kaynağı olmayan anlatımlar iPhone'un kendi çevirisiyle Türkçeye çevrilir.
        .translationHost()
        .task {
            openLaunchScreen()
            askLocationOnce()
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

    /// Haritalar her ekranda canlı konumu göstersin: ilk açılışta bir kez izin sorulur.
    private func askLocationOnce() {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "screen") != nil { return }
        #endif
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
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
        let city = store.cities.first { $0.name == "Tokyo" }?.name ?? store.cities.first?.name ?? "Tokyo"
        let firstPlace = store.places(in: city).first
        let stop = store.stops(in: city).first?.id ?? UUID()
        switch screen {
        case "trips": _ = demoJourney()
        case "journey", "flight", "stay", "addCity": path = [.journey(demoJourney())]
        case "newTrip": sheet = .newTrip
        case "newTripCollection": _ = demoCollection(); sheet = .newTrip
        case "tripFromCollection":
            if let id = store.createJourney(from: demoCollection()) {
                store.dismissUndo()
                path = [.journey(id)]
            }
        case "discover", "discoverTall": tab = .discover
        case "collections", "newCollection": _ = demoCollection()
        case "collection": path = [.collection(demoCollection())]
        case "profile", "settings": tab = .profile
        case "saveTo": tab = .discover; _ = demoCollection(); path = [.country("JP")]
        case "continent": tab = .discover; path = [.continent("asia")]
        case "country": tab = .discover; path = [.country("JP")]
        case "cityGuide", "addToPlan":
            tab = .discover
            path = [.cityGuide(CityChoice(name: "Kyoto", countryCode: "JP", latitude: 35.0116, longitude: 135.7681,
                                          englishTitle: "Kyoto"))]
        case "saved": path = [.saved]
        case "downloads": path = [.downloads]
        case "city", "cityTall", "spot", "moved", "movedList", "photo", "sheetTall", "all", "listen", "pins",
             "reorder", "editPlace":
            path = [.plan(stop)]
        case "player":
            path = [.plan(stop)]
            Narrator.shared.speak("Sensō-ji, Tokyo'nun Asakusa semtinde bulunan eski bir Budist tapınağıdır. "
                                  + "Tokyo'nun en eski tapınağıdır ve her yıl milyonlarca kişi ziyaret eder.",
                                  title: "Sensō-ji", language: "tr")
        case "guide":
            let places = store.places(in: city)
            if let target = places.first(where: { $0.name == "Tokyo Skytree" }) ?? places.first {
                guidance = GuidanceDestination(place: target)
            }
        case "place": if let firstPlace { path = [.plan(stop), .place(firstPlace.id)] }
        case "walk": path = [.plan(stop), .walk(stop: stop, day: 0)]
        case "add", "addSearch": sheet = .addPlace(city: city, stop: stop)
        case "search", "searchSave": sheet = .search(city: city)
        case "import": sheet = .importData
        case "camera": sheet = .camera
        case "custom": sheet = .customPlace(city: city)
        default: break
        }
        #endif
    }

    #if DEBUG
    /// Ekran görüntüleri için örnek koleksiyonlar (yerler, şehir, ülkeler).
    private func demoCollection() -> UUID {
        if let existing = store.collections.first(where: { $0.name == "Tokyo favorileri" }) { return existing.id }
        let europe = store.createCollection(name: "Avrupa hayalleri", emoji: "🏛️", color: 0)
        for code in ["IT", "FR", "GR"] {
            if let country = Country.find(code) { store.toggle(.country(country), in: europe) }
        }
        let id = store.createCollection(name: "Tokyo favorileri", emoji: "🍜", color: 2)
        for place in store.places(in: "Tokyo").prefix(5) { store.toggle(.place(place), in: id) }
        store.toggle(.city(CityChoice(name: "Kyoto", countryCode: "JP", latitude: 35.0116, longitude: 135.7681,
                                      englishTitle: "Kyoto")), in: id)
        if let japan = Country.find("JP") { store.toggle(.country(japan), in: id) }
        store.dismissUndo()
        return id
    }

    /// Ekran görüntüleri için örnek çok şehirli gezi (Polarsteps'teki İstanbul → Ankara gibi).
    private func demoJourney() -> UUID {
        if let existing = store.journeys.first(where: { $0.name == "Türkiye" }) { return existing.id }
        let id = store.createJourney(name: "Türkiye", cities: [
            CityChoice(name: "İstanbul", countryCode: "TR", latitude: 41.0082, longitude: 28.9784, englishTitle: "Istanbul"),
            CityChoice(name: "Ankara", countryCode: "TR", latitude: 39.9334, longitude: 32.8597, englishTitle: "Ankara"),
            CityChoice(name: "Kapadokya", countryCode: "TR", latitude: 38.6431, longitude: 34.8289, englishTitle: "Cappadocia"),
        ])
        if let istanbul = store.journey(id)?.stops.first?.id { store.setDays(3, stop: istanbul) }
        if let stops = store.journey(id)?.stops, stops.count == 3 {
            store.addStay(Stay(name: "Pera Palace Hotel", latitude: 41.0319, longitude: 28.9747, nights: 2),
                          stop: stops[0].id, in: id)
            store.setFlight(Flight(from: "Ankara", number: "TK 2006", departure: "09:40"), stop: stops[2].id, in: id)
        }
        store.dismissUndo()
        return id
    }
    #endif
}

/// Uygulama genelinde açılan alt pencereler.
enum AddSheet: Identifiable {
    /// Gezi şehrine yer ekle (eklenen yer o şehrin rotasına, seçili güne girer).
    case addPlace(city: String, stop: UUID, day: Int = 0)
    /// Alttaki büyüteç: genel arama (eklerken gezi ya da koleksiyon sorulur).
    case search(city: String)
    case customPlace(city: String)
    case importData
    case importFile(URL)
    case camera
    case newTrip

    var id: String {
        switch self {
        case .addPlace(_, let stop, let day): "add-\(stop)-\(day)"
        case .search(let city): "search-\(city)"
        case .customPlace(let city): "custom-\(city)"
        case .importData: "import"
        case .importFile(let url): "import-\(url.lastPathComponent)"
        case .camera: "camera"
        case .newTrip: "newTrip"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .addPlace(let city, let stop, let day): AddPlaceView(city: city, stop: stop, day: day)
        case .search(let city): AddPlaceView(city: city)
        case .customPlace(let city): CustomPlaceView(city: city)
        case .importData: ImportView()
        case .importFile(let url): ImportView(initialFile: url)
        case .camera: CameraAddView()
        case .newTrip: NewTripView(mode: .new)
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
                item(.map, "Harita", "map")
                item(.discover, "Keşfet", "globe.europe.africa")
                item(.profile, "Profil", "person.crop.circle")
            }
            .padding(6)
            .background(.white, in: Capsule())
            .softShadow()

            // Genel arama: bulunan yer kaydedilir, sonra gezinin bir gününe ya
            // da koleksiyona eklenir (haritada bakılan şehrin çevresinde arar).
            Button { sheet = .search(city: city) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.ink, in: Circle())
                    .softShadow()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Ara"))
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
            .frame(width: 84, height: 44)
            .background(tab == value ? Theme.surface : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

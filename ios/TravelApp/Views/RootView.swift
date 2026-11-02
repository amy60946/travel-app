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
    /// Herkese açık paylaşılan gezi (sunucudaki kimliği).
    case sharedTrip(UUID)
    /// Bir gezginin herkese açık gezileri.
    case traveler(UUID)
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
                case .sharedTrip(let id): SharedTripView(tripID: id, path: $path).narrationBarInset()
                case .traveler(let id): TravelerView(ownerID: id, path: $path).narrationBarInset()
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
            // Paylaşılan geziler değişince sunucudaki kopyaları güncellenir.
            TripSharing.shared.startSync(with: store)
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
        case "journey", "flight", "stay", "addCity", "transport", "swipeDelete", "journeyFull":
            path = [.journey(demoJourney())]
        case "newTrip": present(.newTrip)
        case "newTripCollection": _ = demoCollection(); present(.newTrip)
        case "tripFromCollection":
            if let id = store.createJourney(from: demoCollection()) {
                store.dismissUndo()
                path = [.journey(id)]
            }
        case "discover", "discoverTall": tab = .discover
        case "collections", "newCollection": _ = demoCollection()
        case "collection": path = [.collection(demoCollection())]
        case "profile", "settings", "profileShared": tab = .profile
            if screen == "profileShared" { TripSharing.shared.demoMarkShared(demoJourney()) }
        case "editProfile": tab = .profile; present(.editProfile)
        case "shareTrip":
            let id = demoJourney()
            TripSharing.shared.demoMarkShared(id)
            path = [.journey(id)]
        case "sharedTrip": tab = .discover; open([.sharedTrip(SampleData.sharedTrips()[0].id)])
        case "traveler": tab = .discover; open([.traveler(SampleData.sharedTrips()[0].owner)])
        case "searchTrips": tab = .discover
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
             "reorder", "editPlace", "fewerDays", "mapAdd", "mapAdded", "dayOrder", "timed":
            // `fewerDays`: gün sayısı 3'ten 2'ye inmiş (3. günün yerleri yerinde kalır).
            if screen == "fewerDays" { store.setDays(2, stop: stop) }
            // `timed`: 1. günde yemek yerine 19:00 verilmiş ve akıllı sıra uygulanmış.
            if screen == "timed", let firstDay = store.dayPlan(stop: stop).first, firstDay.count > 1 {
                if let food = firstDay.first(where: { $0.category == .food }) {
                    store.setTime(19 * 60, for: food, stop: stop)
                }
                let stops = store.dayStops(store.dayPlan(stop: stop)[0], stop: stop)
                if let best = DayPlanner.smartOrders(stops).first {
                    store.applyOrder(best.map(\.id), day: 0, stop: stop, smart: true)
                }
            }
            store.dismissUndo()
            // Veri değişikliğiyle aynı anda açılan sayfa bazen hiç açılmıyordu;
            // ana sayfa yerleşince açılsın.
            open([.plan(stop)])
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
        case "walk", "walkPlaying": path = [.plan(stop), .walk(stop: stop, day: 0)]
        case "add", "addSearch": present(.addPlace(city: city, stop: stop))
        case "search", "searchSave": present(.search(city: city))
        case "import": present(.importData)
        case "camera": present(.camera)
        case "custom": present(.customPlace(city: city))
        default: break
        }
        #endif
    }

    /// Alttaki sekme çubuğunun yüksekliği (ekranın alt güvenli alanı hariç);
    /// paneller küçükken bunun üstünde durur.
    static let tabBarHeight: CGFloat = 58

    #if DEBUG
    /// Açılışta sayfa, ana sayfa yerleştikten sonra açılsın.
    private func open(_ routes: [Route]) {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            path = routes
        }
    }

    /// Açılışta pencere, ana sayfa yerleştikten sonra açılsın (hemen
    /// açılınca bazen hiç görünmüyordu).
    private func present(_ launchSheet: AddSheet) {
        Task {
            try? await Task.sleep(for: .seconds(1))
            sheet = launchSheet
        }
    }

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
    /// Profil → Düzenle (ad ve simge).
    case editProfile

    var id: String {
        switch self {
        case .addPlace(_, let stop, let day): "add-\(stop)-\(day)"
        case .search(let city): "search-\(city)"
        case .customPlace(let city): "custom-\(city)"
        case .importData: "import"
        case .importFile(let url): "import-\(url.lastPathComponent)"
        case .camera: "camera"
        case .newTrip: "newTrip"
        case .editProfile: "editProfile"
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
        case .editProfile: ProfileEditor()
        }
    }
}

/// Alt çubuk: ekranın iki kenarına ve en altına oturan beyaz çubuk
/// (Harita · Keşfet · Profil) ve sağda siyah büyüteç (genel arama). Panellerin
/// beyazıyla birleşir; arkasında başka menü yok.
private struct TabBar: View {
    @Binding var tab: RootTab
    @Binding var sheet: AddSheet?
    let city: String

    var body: some View {
        HStack(spacing: 0) {
            item(.map, "Harita", "map")
            item(.discover, "Keşfet", "globe.europe.africa")
            item(.profile, "Profil", "person.crop.circle")

            // Genel arama: bulunan yer kaydedilir, sonra gezinin bir gününe ya
            // da koleksiyona eklenir (haritada bakılan şehrin çevresinde arar).
            Button { sheet = .search(city: city) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.ink, in: Circle())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Ara"))
        }
        .padding(.horizontal, 8)
        .frame(height: RootView.tabBarHeight)
        .background {
            Color.white
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairlineLight).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ value: RootTab, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button {
            tab = value
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(Theme.font(11, .semibold))
            }
            .foregroundStyle(tab == value ? Theme.ink : Theme.muted.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: RootView.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}

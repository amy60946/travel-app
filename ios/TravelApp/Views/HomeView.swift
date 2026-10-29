import MapKit
import SwiftUI

/// Ana sayfa: Google Maps gibi çalışan harita. Uzaktan bakınca
/// kürede şehir pinleri; yaklaşınca kayıtlı yerler türlerinin renk ve
/// simgesiyle (müze mor, kafe kahverengi, tapınak kırmızı...). Üstte arama
/// ("Yer ekle" listesini açar), sağda harita türü ve konumum. Haritadaki
/// herhangi bir yere (Apple'ın müze, kafe... yerleri) dokunup tek dokunuşla
/// kaydedilir. Altta Gezilerim / Kayıtlarım listesi.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var path: [Route]
    @StateObject private var importer = PlaceImporter()

    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: .init(latitude: 35.68, longitude: 139.76), distance: 30_000_000))
    @State private var distance: Double = 30_000_000
    @State private var region: MKCoordinateRegion?
    @State private var mapKind: MapKind = .standard
    @State private var section = 0
    @State private var panelExpanded = true

    @State private var addCity = ""
    @State private var showAdd = false

    @State private var selectedFeature: MapFeature?
    /// Alttan açılan yer penceresi (fotoğraflar, Dinle, bilgi).
    @State private var sheetPlaceID: UUID?
    @State private var card: Card?
    /// Kart haritadaki bir Apple yerine dokunularak mı açıldı?
    @State private var cardFromFeature = false
    @State private var saving = false
    @State private var detailItem: MKMapItem?
    @State private var locationManager = CLLocationManager()
    /// Haritanın ekrandaki yüksekliği (yer penceresi yarısını kaplar).
    @State private var mapHeight: CGFloat = 800
    /// Alttaki panelin üst kenarı ve listenin yüksekliği: panel içeriği
    /// kadar yer kaplar (tek gezi varsa altta boşluk kalmaz).
    @State private var panelTop: CGFloat = 500
    @State private var listHeight: CGFloat = 0
    @State private var showLocationDenied = false

    /// Haritada dokunulan, henüz kaydedilmemiş Apple yerinin kartı.
    private enum Card: Equatable {
        case item(MKMapItem, PlaceCategory)
        case loading
    }

    /// Bu yükseklikten (metre) yakına inince şehir pinleri yerine yerler görünür.
    private static let placesDistance: Double = 400_000
    private var isZoomedIn: Bool { distance < Self.placesDistance }
    /// Şehir görünümünde yalnızca bizim pinler; sokak düzeyinde Apple'ın yerleri de.
    private var showsApplePlaces: Bool { distance < 4_000 }
    /// Az yer görünüyorsa ya da yakındaysak pinlerin adları da yazılır.
    private var showsTitles: Bool { distance < 12_000 || visiblePlaces.count <= 20 }

    private var listedCities: [AppStore.CitySummary] {
        section == 0 ? store.cities.filter(\.hasTrip) : store.cities
    }

    /// Görünen bölgedeki kayıtlı yerler.
    private var visiblePlaces: [Place] {
        var list = store.places
        if let region {
            list = list.filter {
                abs($0.latitude - region.center.latitude) < region.span.latitudeDelta
                    && abs($0.longitude - region.center.longitude) < region.span.longitudeDelta
            }
        }
        return Array(list.prefix(300))
    }

    var body: some View {
        ZStack(alignment: .top) {
            map

            VStack(alignment: .leading, spacing: 10) {
                topBar
                HStack(alignment: .top) {
                    Spacer()
                    controls
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
                bottom
            }
        }
        .task {
            centerOnCities()
            await openLaunchScreen()
        }
        .onChange(of: store.cities.map(\.name)) {
            if !isZoomedIn { centerOnCities() }
        }
        .onChange(of: isZoomedIn) { _, zoomedIn in
            withAnimation(.snappy) { panelExpanded = !zoomedIn }
        }
        .onChange(of: selectedFeature) { _, feature in
            Task { await show(feature) }
        }
        .appleDetailSheet(item: $detailItem)
        .sheet(isPresented: $showAdd) { AddPlaceView(city: addCity) }
        .sheet(isPresented: Binding(get: { sheetPlaceID != nil }, set: { if !$0 { sheetPlaceID = nil } })) {
            if let id = sheetPlaceID {
                PlaceSheet(placeID: id) { place in open(place) }
                    .placeSheetPresentation()
            }
        }
        .alert("Konum izni kapalı", isPresented: $showLocationDenied) {
            Button("Ayarları aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Konumunu haritada görmek için Ayarlar'da Location → While Using the App seç.")
        }
    }

    // MARK: - Harita

    private var map: some View {
        // Döndürme kapalı: pusula olmadan kuzey hep yukarıda kalsın.
        Map(position: $position, interactionModes: [.pan, .zoom], selection: $selectedFeature) {
            if isZoomedIn {
                ForEach(visiblePlaces) { place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        Button { select(place) } label: {
                            CategoryPin(category: place.category, size: sheetPlaceID == place.id ? 42 : 32)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(showsTitles || sheetPlaceID == place.id ? .visible : .hidden)
                }
            } else {
                ForEach(store.cities) { city in
                    Annotation(city.name, coordinate: city.coordinate, anchor: .bottom) {
                        Button { path.append(.city(city.name)) } label: {
                            CityPin(city: city)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            UserAnnotation()
        }
        .mapStyle(mapKind.exploreStyle(showingApplePlaces: showsApplePlaces))
        .onMapCameraChange(frequency: .onEnd) { context in
            distance = context.camera.distance
            region = context.region
        }
        // Harita alttaki panelin ya da yer penceresinin üstünde, görünen
        // alanın ortasında dursun.
        .safeAreaPadding(.bottom, sheetPlaceID != nil ? mapHeight / 2
                          : panelExpanded && card == nil ? max(mapHeight - panelTop, 170) : 170)
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapHeight = $0 }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Polarsteps'teki gibi: arama "Yer ekle" listesini açar.
            Button {
                addCity = nearestCity
                showAdd = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    Text("Yer ara ve ekle").foregroundStyle(Theme.muted)
                    Spacer()
                }
                .font(Theme.font(16))
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.white, in: Capsule())
                .softShadow()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    /// Sağdaki düğmeler: harita türü ve konumum.
    private var controls: some View {
        VStack(spacing: 10) {
            MapKindMenu(selection: $mapKind)
            CircleIconButton(systemImage: "location", action: showMyLocation)
                .accessibilityLabel(Text("Konumum"))
        }
    }

    // MARK: - Alt bölüm

    @ViewBuilder
    private var bottom: some View {
        Group {
            if let card {
                cardView(card)
            } else if panelExpanded {
                bottomPanel
            } else {
                collapsedPanel
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.snappy, value: card)
    }

    @ViewBuilder
    private func cardView(_ card: Card) -> some View {
        switch card {
        case .loading:
            MapPlaceCard(category: .other, title: String(localized: "Yükleniyor…"), subtitle: "", onClose: closeCard) {
                ProgressView()
            }
            .floatingAboveTabBar()
        case .item(let item, let category):
            MapPlaceCard(category: category, title: item.name ?? "",
                         subtitle: [category.title, item.placemark.title ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                         onClose: closeCard) {
                PrimaryButton(title: saving ? LocalizedStringKey("Kaydediliyor…") : LocalizedStringKey("Kaydet"),
                              systemImage: "bookmark") {
                    Task { await save(item, category: category) }
                }
                .disabled(saving)
                SecondaryButton(title: "Ayrıntılar", systemImage: "info.circle") { detailItem = item }
                DirectionsButton { PlaceSearch.openDirections(to: item) }
            }
            .floatingAboveTabBar()
        }
    }

    private var collapsedPanel: some View {
        Button {
            withAnimation(.snappy) { panelExpanded = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                Text("Gezilerim ve kayıtlarım")
            }
            .font(Theme.font(14, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white, in: Capsule())
            .softShadow()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 84)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { panelExpanded = false }
            } label: {
                Capsule().fill(Theme.hairline)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Paneli küçült"))

            Picker("", selection: $section) {
                Text("Gezilerim").tag(0)
                Text("Kayıtlarım").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            if listedCities.isEmpty {
                Text(section == 0
                     ? LocalizedStringKey("Henüz gezi yok. Kayıtlarım'dan bir şehir seç, rota oluştur.")
                     : LocalizedStringKey("Henüz kayıt yok. + ile yer ekle ya da veri aktar."))
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(listedCities) { city in
                        Button { path.append(.city(city.name)) } label: {
                            CityRow(city: city, days: store.trip(for: city.name).days)
                        }
                        .buttonStyle(.plain)
                        if city.id != listedCities.last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, 220))
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .padding(.top, -6)
        .padding(.bottom, 80)
        .background {
            // Panel ekranın alt kenarına kadar uzansın; altta harita görünmesin.
            UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius, topTrailingRadius: Theme.sheetRadius)
                .fill(.white)
                .ignoresSafeArea(edges: .bottom)
        }
        .softShadow()
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { panelTop = $0 }
    }

    // MARK: - İşlemler

    private func isShowing(_ item: MKMapItem) -> Bool {
        if case .item(let shown, _) = card { return shown == item }
        return false
    }

    /// Yerin penceresini açar; harita o yere ve yanındaki yerlere yakınlaşır.
    private func select(_ place: Place) {
        cardFromFeature = false
        selectedFeature = nil
        card = nil
        sheetPlaceID = place.id
        withAnimation {
            position = .region(MKCoordinateRegion(focusing: place, among: store.places(in: place.city)))
        }
    }

    /// Yer penceresinden tam yer sayfasına geçer (pencere kapanınca).
    private func open(_ place: Place) {
        sheetPlaceID = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            path.append(.place(place.id))
        }
    }

    /// Haritada Apple'ın bir yerine (müze, kafe, istasyon...) dokunuldu.
    private func show(_ feature: MapFeature?) async {
        guard let feature else {
            if cardFromFeature { card = nil }
            cardFromFeature = false
            return
        }
        cardFromFeature = true
        card = .loading
        let item = await PlaceSearch.mapItem(for: feature)
        guard selectedFeature == feature, cardFromFeature else { return }
        guard let item else {
            card = nil
            return
        }
        if let saved = store.savedPlace(named: item.name ?? "", near: item.placemark.coordinate) {
            select(saved)
        } else {
            card = .item(item, PlaceCategory(item))
        }
    }

    private func closeCard() {
        cardFromFeature = false
        selectedFeature = nil
        card = nil
    }

    /// Yeri kaydeder (rotaya eklemez); şehir konumdan bulunur.
    private func save(_ item: MKMapItem, category: PlaceCategory) async {
        let coordinate = item.placemark.coordinate
        guard store.savedPlace(named: item.name ?? "", near: coordinate) == nil else { return }
        saving = true
        defer { saving = false }
        let city = await importer.city(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                       knownCities: store.cities)
        let place = Place(name: item.name ?? String(localized: "Yer"), city: city,
                          latitude: coordinate.latitude, longitude: coordinate.longitude,
                          category: category, source: .search)
        store.add(place, plan: false)
        if isShowing(item) { select(place) }
    }

    private func showMyLocation() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDenied = true
        default:
            locationManager.requestWhenInUseAuthorization()
            withAnimation { position = .userLocation(fallback: position) }
        }
    }

    /// "Yer ekle" hangi şehir için açılsın: haritanın ortasına en yakın şehir.
    private var nearestCity: String {
        let cities = store.cities
        guard isZoomedIn, let center = region?.center else { return cities.first?.name ?? "Tokyo" }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return cities.min {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
        }?.name ?? "Tokyo"
    }

    /// Küreyi kayıtlı şehirlerin ortasına çevirir.
    private func centerOnCities() {
        let cities = store.cities
        guard !cities.isEmpty else { return }
        let latitude = cities.map(\.latitude).reduce(0, +) / Double(cities.count)
        let longitude = cities.map(\.longitude).reduce(0, +) / Double(cities.count)
        position = .camera(MapCamera(centerCoordinate: .init(latitude: latitude, longitude: longitude),
                                     distance: 30_000_000))
    }

    /// Yalnızca geliştirme sürümünde: `-screen map` ilk şehre yaklaşır,
    /// `-screen sheet` ayrıca ilk yerin penceresini açar (ekran görüntüleri için).
    private func openLaunchScreen() async {
        #if DEBUG
        let screen = UserDefaults.standard.string(forKey: "screen")
        guard screen == "map" || screen == "sheet", let city = store.cities.first,
              let region = MKCoordinateRegion(fitting: store.places(in: city.name).map(\.coordinate))
        else { return }
        position = .region(region)
        if screen == "sheet", let place = store.places(in: city.name).first {
            try? await Task.sleep(for: .seconds(1))
            select(place)
        }
        #endif
    }
}

/// Alttaki listede bir şehir: fotoğraf, ad, gün ve yer sayısı.
private struct CityRow: View {
    let city: AppStore.CitySummary
    let days: Int

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover = city.coverPlace {
                    PlaceThumbnail(place: cover, cornerRadius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                        .overlay(Image(systemName: "mappin").foregroundStyle(Theme.muted))
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(city.name).font(Theme.font(17, .semibold))
                Text(city.hasTrip
                     ? LocalizedStringKey("\(days) gün · \(city.placeCount) yer")
                     : LocalizedStringKey("\(city.placeCount) kayıtlı yer · rota yok"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if city.hasTrip {
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            } else {
                Text("Rota oluştur").font(Theme.font(14, .semibold)).underline()
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Kürede şehir pini: fotoğraf + ad + yer sayısı; sıradaki gezi siyah.
private struct CityPin: View {
    let city: AppStore.CitySummary

    var body: some View {
        HStack(spacing: 6) {
            if let cover = city.coverPlace {
                PlaceThumbnail(place: cover, cornerRadius: 12)
                    .frame(width: 24, height: 24)
            }
            Text("\(city.name) · \(city.placeCount)")
                .font(Theme.font(13, .semibold))
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .foregroundStyle(city.hasTrip ? .white : Theme.ink)
        .background(city.hasTrip ? Theme.ink : .white, in: Capsule())
        .softShadow()
    }
}

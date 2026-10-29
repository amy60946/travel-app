import MapKit
import SwiftUI

/// Ana sayfa: Google Maps gibi çalışan Google haritası. Uzaktan bakınca
/// şehir pinleri; yaklaşınca kayıtlı yerler türlerinin renk ve simgesiyle
/// (müze mor, kafe kahverengi, tapınak kırmızı...). Sağ üstte ayarlar,
/// harita türü ve konumum; arama sağ alttaki büyüteçte ("Yer ekle").
/// Haritadaki herhangi bir yere (Google'ın restoran, müze, kafe... yerleri)
/// dokununca Google'ın puanı, yorumları ve fotoğraflarıyla penceresi açılır,
/// tek dokunuşla kaydedilir. Altta Gezilerim (çok şehirli geziler, "Yeni
/// gezi") / Kayıtlarım (şehirler) listesi.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var path: [Route]
    /// Sağ alttaki büyüteç "Yer ekle"yi bu şehir için açar: haritanın ortasına en yakın şehir.
    @Binding var searchCity: String
    /// Uygulama genelindeki alt pencere ("Yeni gezi" buradan açılır).
    @Binding var sheet: AddSheet?

    @State private var mapFocus: MapFocus?
    /// Haritanın şu an gösterdiği alan (kaydırma bitince güncellenir).
    @State private var viewport: MapViewport?
    @State private var mapKind: MapKind = .standard
    @State private var section = 0
    /// Alttaki panel: küçük (yalnızca sekmeler), içeriği kadar, büyük.
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 300

    /// Alttan açılan yer penceresi: kayıtlı yer ya da Google'ın bir yeri.
    @State private var mapSheet: MapSheet?
    @State private var sheetDetent: PresentationDetent = .placeHalf
    @State private var locationManager = CLLocationManager()
    /// Haritanın ekrandaki yüksekliği (yer penceresi yarısını kaplar).
    @State private var mapHeight: CGFloat = 800
    /// Listenin yüksekliği: panelin orta yüksekliği içeriği kadar olur
    /// (tek gezi varsa altta boşluk kalmaz).
    @State private var listHeight: CGFloat = 160
    @State private var showLocationDenied = false
    @State private var showSettings = false
    @AppStorage(PinStyle.storageKey) private var pinStyle = PinStyle.icon
    @ObservedObject private var pinPhotos = PinPhotos.shared

    private enum MapSheet: Identifiable, Equatable {
        case saved(UUID)
        case google(GooglePlaceRef)

        var id: String {
            switch self {
            case .saved(let id): id.uuidString
            case .google(let place): place.id
            }
        }
    }

    /// Açık penceredeki kayıtlı yer (pini büyük görünür).
    private var sheetPlaceID: UUID? {
        if case .saved(let id) = mapSheet { return id }
        return nil
    }

    private var zoom: Float { viewport?.zoom ?? 2 }
    /// Bu yakınlıktan sonra şehir pinleri yerine yerler görünür.
    private var isZoomedIn: Bool { zoom > 7.5 }
    /// Az yer görünüyorsa ya da yakındaysak pinlerin adları da yazılır.
    private var showsTitles: Bool { zoom >= 13.5 || visiblePlaces.count <= 20 }

    /// Kayıtlarım: kayıtlı yeri olan şehirler.
    private var listedCities: [AppStore.CitySummary] {
        store.cities.filter { $0.placeCount > 0 }
    }

    /// Görünen bölgedeki (ve kenarındaki) kayıtlı yerler.
    private var visiblePlaces: [Place] {
        var list = store.places
        if let region = viewport?.region {
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

            HStack(alignment: .top) {
                Spacer()
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            bottom
        }
        .task {
            centerOnCities()
            pinPhotos.load(store.cities.compactMap(\.coverPlace))
            await openLaunchScreen()
        }
        .onChange(of: store.cities.map(\.name)) {
            if !isZoomedIn { centerOnCities() }
            pinPhotos.load(store.cities.compactMap(\.coverPlace))
        }
        .onChange(of: isZoomedIn) { _, zoomedIn in
            withAnimation(.snappy) { panelStop = zoomedIn ? 0 : 1 }
        }
        .onChange(of: pinStyle) { loadPinPhotos() }
        .sheet(item: $mapSheet) { shown in
            Group {
                switch shown {
                case .saved(let id):
                    PlaceSheet(placeID: id) { place in open(place) }
                case .google(let place):
                    GooglePlaceSheet(place: place) { saved in select(saved) }
                }
            }
            .placeSheetPresentation(detent: $sheetDetent)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
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
        // Harita alttaki panelin ya da yer penceresinin üstünde, görünen
        // alanın ortasında dursun.
        GoogleMap(focus: $mapFocus, markers: markers, kind: mapKind,
                  padding: EdgeInsets(top: 0, leading: 0,
                                      bottom: mapSheet != nil ? mapHeight / 2 - 30 : panelHeight,
                                      trailing: 0),
                  onPlaceTap: { id, name, coordinate in showGooglePlace(id: id, name: name, coordinate: coordinate) },
                  onMapTap: {
                      // Yer penceresi uzunken haritaya dokununca pencere yarıya iner.
                      if mapSheet != nil, sheetDetent == .placeTall { sheetDetent = .placeHalf }
                  },
                  onCameraIdle: { shown in
                      viewport = shown
                      searchCity = nearestCity
                      loadPinPhotos()
                  })
            .ignoresSafeArea()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapHeight = $0 }
    }

    /// Yakından kayıtlı yerler (Ayarlar'a göre simge ya da fotoğraf),
    /// uzaktan şehirler.
    private var markers: [GoogleMap.Marker] {
        guard isZoomedIn else {
            return store.cities.map { city in
                let photo = city.coverPlace.flatMap { pinPhotos.image(for: $0) }
                return GoogleMap.Marker(id: "city-\(city.name)", coordinate: city.coordinate,
                                        key: "\(city.name)|\(city.placeCount)|\(city.hasTrip)|\(photo.map { "\($0.hash)" } ?? "-")",
                                        anchorsBottom: true, onTap: { path.append(.city(city.name)) }) {
                    CityPin(city: city, photo: photo).padding(6)
                }
            }
        }
        let titles = showsTitles
        return visiblePlaces.map { place in
            let selected = sheetPlaceID == place.id
            return GoogleMap.Marker.place(place, size: selected ? 42 : 32,
                                          photo: pinStyle == .photo ? pinPhotos.image(for: place) : nil,
                                          showsTitle: titles || selected, zIndex: selected ? 1 : 0) { select(place) }
        }
    }

    /// Fotoğraflı pin seçiliyse görünen yerlerin fotoğrafları.
    private func loadPinPhotos() {
        guard pinStyle == .photo, isZoomedIn else { return }
        pinPhotos.load(visiblePlaces)
    }

    /// Sağdaki düğmeler: ayarlar (dil), harita türü ve konumum.
    private var controls: some View {
        VStack(spacing: 10) {
            CircleIconButton(systemImage: "gearshape") { showSettings = true }
                .accessibilityLabel(Text("Ayarlar"))
            MapKindMenu(selection: $mapKind)
            CircleIconButton(systemImage: "location", action: showMyLocation)
                .accessibilityLabel(Text("Konumum"))
        }
    }

    // MARK: - Alt bölüm

    private var bottom: some View {
        DraggablePanel(stops: panelStops, selection: $panelStop, onSettle: { panelHeight = $0 }) {
            Picker("", selection: $section) {
                Text("Gezilerim").tag(0)
                Text("Kayıtlarım").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        } content: {
            panelList
        }
    }

    /// Panelin yükseklikleri: yalnızca sekmeler (altta sekme çubuğu), içeriği
    /// kadar (en çok yarım ekran), büyük (üstteki düğmeler görünür kalır).
    private var panelStops: [PanelStop] {
        let tabBar: CGFloat = 96
        let fitting = min(64 + listHeight + tabBar, mapHeight * 0.5)
        return [.height(150), .height(max(fitting, 151)), .fraction(0.85)]
    }

    private var panelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if section == 1 && listedCities.isEmpty {
                Text("Henüz kayıt yok. Büyüteçle yer ekle ya da veri aktar.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
            }
            if section == 0 {
                ForEach(store.journeys) { journey in
                    Button { path.append(.journey(journey.id)) } label: { journeyRow(journey) }
                        .buttonStyle(.plain)
                    Divider().padding(.leading, 70)
                }
                Button { sheet = .newTrip } label: { newTripRow }
                    .buttonStyle(.plain)
            } else {
                ForEach(listedCities) { city in
                    Button { open(city) } label: {
                        CityRow(city: city, days: store.trip(for: city.name).days)
                    }
                    .buttonStyle(.plain)
                    if city.id != listedCities.last?.id {
                        Divider().padding(.leading, 70)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        // Altta yüzen sekme çubuğu son satırı örtmesin.
        .padding(.bottom, 96)
    }

    private func journeyRow(_ journey: Journey) -> some View {
        let first = journey.stops.first
        let days = store.days(of: journey).reduce(0, +)
        let planned = journey.stops.reduce(0) { $0 + store.trip(for: $1.city).placeIDs.count }
        return HStack(spacing: 14) {
            CityPhoto(name: first?.city ?? "", englishTitle: first?.englishTitle,
                      cover: store.cities.first { $0.name == first?.city }?.coverPlace)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(journey.name).font(Theme.font(17, .semibold)).lineLimit(1)
                Text(journey.stops.count > 1
                     ? String(localized: "\(journey.stops.count) şehir · \(days) gün")
                     : String(localized: "\(days) gün · \(planned) yer"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var newTripRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("Yeni gezi").font(Theme.font(17, .semibold))
                Text("Şehirleri seç, sırayla planla").font(Theme.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - İşlemler

    /// Kayıtlarım'da şehre dokununca: gezisi varsa gezi planı, yoksa şehrin planı.
    private func open(_ city: AppStore.CitySummary) {
        if let journey = store.journey(containing: city.name) {
            path.append(.journey(journey.id))
        } else {
            path.append(.city(city.name))
        }
    }

    /// Yerin penceresini açar; harita o yere ve yanındaki yerlere yakınlaşır.
    private func select(_ place: Place) {
        sheetDetent = .placeHalf
        mapSheet = .saved(place.id)
        mapFocus = .region(MKCoordinateRegion(focusing: place, among: store.places(in: place.city)))
    }

    /// Yer penceresinden tam yer sayfasına geçer (pencere kapanınca).
    private func open(_ place: Place) {
        mapSheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            path.append(.place(place.id))
        }
    }

    /// Haritada Google'ın bir yerine (restoran, müze, istasyon...) dokunuldu:
    /// kayıtlıysa kendi penceresi, değilse Google'ın bilgileriyle pencere.
    private func showGooglePlace(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        let name = name.replacingOccurrences(of: "\n", with: " ")
        if let saved = store.savedPlace(googleID: id, named: name, near: coordinate) {
            select(saved)
            return
        }
        sheetDetent = .placeHalf
        mapSheet = .google(GooglePlaceRef(id: id, name: name, coordinate: coordinate))
    }

    private func showMyLocation() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDenied = true
        default:
            locationManager.requestWhenInUseAuthorization()
            mapFocus = .user(zoom: 15)
        }
    }

    /// Büyüteç "Yer ekle"yi hangi şehir için açsın: haritanın ortasına en yakın şehir.
    private var nearestCity: String {
        let cities = store.cities
        guard isZoomedIn, let center = viewport?.region.center else { return cities.first?.name ?? "Tokyo" }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return cities.min {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
        }?.name ?? "Tokyo"
    }

    /// Dünya haritasını kayıtlı şehirlerin ortasına çevirir.
    private func centerOnCities() {
        let cities = store.cities
        guard !cities.isEmpty else { return }
        let latitude = cities.map(\.latitude).reduce(0, +) / Double(cities.count)
        let longitude = cities.map(\.longitude).reduce(0, +) / Double(cities.count)
        mapFocus = .point(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoom: 2, animated: false)
    }

    /// Yalnızca geliştirme sürümünde: `-screen map` ilk şehre yaklaşır,
    /// `-screen sheet` ayrıca ilk yerin penceresini açar (ekran görüntüleri için).
    private func openLaunchScreen() async {
        #if DEBUG
        let screen = UserDefaults.standard.string(forKey: "screen")
        if screen == "settings" { showSettings = true }
        // `googlePlace`: Shibuya'da bir restoranın Google penceresi (puan,
        // fotoğraflar); `googleTall` aynısı uzun (saatler, yorumlar).
        if screen == "googlePlace" || screen == "googleTall" {
            let shibuya = CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)
            mapFocus = .point(shibuya, zoom: 16.5, animated: false)
            guard let found = await GooglePlaces.shared.search("Ichiran Shibuya", near: shibuya).first else { return }
            sheetDetent = .placeHalf
            mapSheet = .google(GooglePlaceRef(id: found.id, name: found.name, coordinate: found.coordinate))
            if screen == "googleTall" {
                try? await Task.sleep(for: .seconds(1.5))
                sheetDetent = .placeTall
            }
            return
        }
        guard screen == "map" || screen == "sheet",
              let city = store.cities.first(where: { $0.name == "Tokyo" }) ?? store.cities.first,
              let region = MKCoordinateRegion(fitting: store.places(in: city.name).map(\.coordinate))
        else { return }
        mapFocus = .region(region, animated: false)
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

/// Dünya haritasında şehir pini: fotoğraf + ad + yer sayısı; gezisi olan
/// şehir siyah. Resme çevrilip haritaya konur (fotoğraf önceden indirilir).
private struct CityPin: View {
    let city: AppStore.CitySummary
    var photo: UIImage?

    var body: some View {
        HStack(spacing: 6) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            }
            Text(city.placeCount > 0 ? "\(city.name) · \(city.placeCount)" : city.name)
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

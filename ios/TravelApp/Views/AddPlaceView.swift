import MapKit
import SwiftUI

/// Yer ekle (Polarsteps'teki "Add a spot" gibi): arama (Google Haritalar),
/// Kendi yerini oluştur, Fotoğrafla ekle, Kayıtlı yerler ve Popüler yerler
/// (Wikipedia okunma sayısı). Her satırda türün renkli etiketi ve "+".
///
/// İki türlü açılır:
/// - Şehir planından: "+" yeri bu şehrin rotasına, sağ üstte seçili güne
///   ekler; ✓ olan yere yeniden dokununca rotadan çıkar. Bir koleksiyonda
///   kayıtlı yer de rotaya eklenebilir (koleksiyonda da kalır).
/// - Genel arama (alttaki büyüteç): "+" yeri kaydeder ve "Nereye
///   eklensin?" penceresini açar: gezilerden birinin bir günü ya da
///   koleksiyonlar. Şehir yalnızca aramanın ve popüler yerlerin merkezi.
struct AddPlaceView: View {
    let city: String
    /// Yerlerin ekleneceği gezi şehri; yoksa genel arama (yer bir rotaya
    /// değil, eklerken seçilen yere gider).
    let stop: UUID?
    private var general: Bool { stop == nil }
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = PlaceImporter()

    @State private var query = ""
    @State private var results: [GooglePlaces.SearchResult] = []
    @State private var searching = false
    @State private var popular: [WikipediaService.PopularPlace] = []
    @State private var popularFailed = false
    @State private var showAllSaved = false
    /// Arama sonucuna dokununca Google'ın bilgileriyle penceresi.
    @State private var detailPlace: GooglePlaceRef?
    @State private var showCustom = false
    @State private var showCamera = false
    /// Eklenen yerlerin günü (şehir planında bakılan gün).
    @State private var day: Int
    /// Genel aramada kaydedilen yer: "Nereye eklensin?" penceresi.
    @State private var destination: Place?
    /// Günün yerlerine yakın popüler yerler (güne yer eklendikçe yenilenir).
    @State private var nearby: [Recommender.Suggestion] = []
    @State private var loadingNearby = false
    @State private var showAllNearby = false
    /// Günde yemek ya da kafe yoksa yakındaki popüler restoran ve kafeler (Google).
    @State private var nearbyFood: [GooglePlaces.SearchResult] = []
    /// Geoapify'dan (OpenStreetMap) yakındaki kafe, restoran, park ve manzara.
    @State private var nearbySpots: [GeoapifyService.Spot] = []
    /// Bu pencerede yakındaki önerilerden eklenenler: yenilenen listede yerinde kalır (✓).
    @State private var addedHere: Set<String> = []
    /// Gerçek yürüme süreleri gelince artar (alt yazılar yenilensin).
    @State private var walkVersion = 0

    init(city: String, stop: UUID? = nil, day: Int = 0) {
        self.city = city
        self.stop = stop
        _day = State(initialValue: day)
    }

    private var center: CLLocationCoordinate2D {
        store.center(of: city) ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
    }

    private func isPlanned(_ place: Place) -> Bool {
        stop.map { store.isPlanned(place, stop: $0) } ?? false
    }

    /// Şehirdeki kayıtlar; rotada olmayanlar önce.
    private var saved: [Place] {
        store.places(in: city).sorted { !isPlanned($0) && isPlanned($1) }
    }

    /// Seçili günün yerleri (yakındaki önerilerin çıkış noktaları).
    private var dayPlaces: [Place] {
        guard let stop else { return [] }
        let days = store.dayPlan(stop: stop)
        return days.indices.contains(day) ? days[day] : []
    }

    /// Öneriler bu değişince yeniden hesaplanır (gün değişti, güne yer eklendi ya da çıkarıldı).
    private var nearbyKey: String {
        "\(day)|" + dayPlaces.map(\.id.uuidString).sorted().joined(separator: ",")
    }

    /// Şehrin popüler yerleri; yakındaki önerilerde görünenler tekrar edilmez.
    private var cityPopular: [WikipediaService.PopularPlace] {
        let shown = Set(nearby.map(\.id))
        return popular.filter { !shown.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    optionRow("Kendi yerini oluştur", systemImage: "mappin.and.ellipse") { showCustom = true }
                    optionRow("Fotoğrafla ekle", systemImage: "camera") { showCamera = true }

                    if !query.isEmpty {
                        sectionTitle("Arama sonuçları")
                        if !searching && results.isEmpty {
                            Text("Sonuç bulunamadı.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        ForEach(results) { result in resultRow(result) }
                        // Google'ın kuralı: haritasız listede Google sonuçlarının kaynağı.
                        if !results.isEmpty {
                            Text(verbatim: "Google Maps")
                                .font(Theme.font(11))
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 6)
                        }
                    }

                    if !dayPlaces.isEmpty { nearbySection }

                    if !saved.isEmpty {
                        sectionTitle("Kayıtlı yerler")
                        ForEach(showAllSaved ? saved : Array(saved.prefix(3))) { place in savedRow(place) }
                        if saved.count > 3 && !showAllSaved {
                            showAllButton
                        }
                    }

                    sectionTitle("Popüler yerler")
                    if popular.isEmpty && !popularFailed {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if popularFailed {
                        Text("Popüler yerler yüklenemedi. İnternet bağlantını kontrol et.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    ForEach(cityPopular) { item in popularRow(item) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(.white)
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .task {
            #if DEBUG
            // `-screen addSearch`: aramada bir otel (fotoğrafı ve köşesinde tür simgesi).
            let screen = UserDefaults.standard.string(forKey: "screen")
            if screen == "addSearch" || screen == "search" { query = "Park Hyatt Tokyo" }
            // `searchSave`: genel aramada kayıtlı bir yerin "Nereye eklensin?" penceresi.
            if screen == "searchSave", let place = store.places(in: city).first {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    destination = place
                }
            }
            #endif
            await loadPopular()
        }
        .task(id: nearbyKey) { await loadNearby() }
        // Yazarken arar (her harfte değil, yazmaya ara verince; her arama
        // Google'ın ücretsiz kotasından düşer).
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await search()
        }
        .sheet(item: $detailPlace) { place in
            GooglePlaceSheet(place: place,
                             context: stop.map { GooglePlaceContext.cityPlan(stop: $0, day: day, fallback: day) } ?? .general) { _ in
                detailPlace = nil
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
        }
        .sheet(isPresented: $showCustom) { CustomPlaceView(city: city, stop: stop, day: day) }
        .sheet(item: $destination) { place in SaveToCollectionSheet(item: .place(place), place: place) }
        .sheet(isPresented: $showCamera) { CameraAddView() }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
        .animation(.snappy, value: store.undoMessage)
    }

    // MARK: - Parçalar

    private var header: some View {
        ZStack {
            Text(general ? LocalizedStringKey("Ara") : LocalizedStringKey("Yer ekle")).font(Theme.font(18, .bold))
            HStack {
                CircleIconButton(systemImage: "xmark") { dismiss() }
                    .accessibilityLabel(Text("Kapat"))
                Spacer()
                if !general { dayMenu }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Hangi güne ekleneceği; tek günlük gezide görünmez.
    @ViewBuilder
    private var dayMenu: some View {
        let days = stop.map { store.trip(stop: $0).days } ?? 1
        if days > 1 {
            Menu {
                Picker("Gün", selection: $day) {
                    ForEach(0..<days, id: \.self) { Text("\($0 + 1). güne ekle").tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text("\(min(day, days - 1) + 1). gün").font(Theme.font(14, .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface, in: Capsule())
            }
            .menuOrder(.fixed)
            .accessibilityHint(Text("Eklenecek günü değiştir"))
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Yer, restoran veya kafe ara", text: $query)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if searching { ProgressView() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Temizle"))
                }
            }
            .font(Theme.font(16))
            .padding(.horizontal, 14)
            .frame(height: 50)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.hairline, lineWidth: 1.5))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func optionRow(_ title: LocalizedStringKey, systemImage: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .frame(width: 52, height: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairlineLight))
                Text(title).font(Theme.font(16, .semibold))
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.font(22, .bold))
            .padding(.top, 26)
            .padding(.bottom, 6)
    }

    private var showAllButton: some View {
        Button { withAnimation { showAllSaved = true } } label: { showAllLabel }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// "Yakınındaki popüler yerler": günün yerlerine yürüme mesafesinde, en
    /// çok gezilenler; günde yemek yoksa altında popüler restoran ve kafeler.
    @ViewBuilder
    private var nearbySection: some View {
        sectionTitle("Yakınındaki popüler yerler")
        if nearby.isEmpty {
            if loadingNearby {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Günündeki yerlerin yakınında popüler bir yer bulunamadı.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
        }
        ForEach(showAllNearby ? nearby : Array(nearby.prefix(6))) { item in nearbyRow(item) }
        if nearby.count > 6 && !showAllNearby {
            Button { withAnimation { showAllNearby = true } } label: { showAllLabel }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        if !nearbyFood.isEmpty {
            Text("Yakında yemek ve kahve")
                .font(Theme.font(15, .bold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 18)
                .padding(.bottom, 2)
            ForEach(nearbyFood) { result in foodRow(result) }
            // Google'ın kuralı: haritasız listede Google sonuçlarının kaynağı.
            Text(verbatim: "Google Maps")
                .font(Theme.font(11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
        }
        if !nearbySpots.isEmpty {
            Text(nearbySpots.contains { Self.isFood($0.category) }
                 ? LocalizedStringKey("Yakında yemek, kahve ve park") : LocalizedStringKey("Yakında park ve manzara"))
                .font(Theme.font(15, .bold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 18)
                .padding(.bottom, 2)
            ForEach(nearbySpots) { spot in spotRow(spot) }
            // Geoapify ve OpenStreetMap lisansı gereği.
            Text(verbatim: "Powered by Geoapify · © OpenStreetMap")
                .font(Theme.font(11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
        }
    }

    nonisolated private static func isFood(_ category: PlaceCategory) -> Bool {
        category == .food || category == .cafe || category == .bar
    }

    /// "yürüyerek 4 dk · Kız Kulesi yakınında": süre önde, satıra sığmasa da
    /// görünür. Gerçek yürüme süresi biliniyorsa o (en kısa yürünen yer).
    private func walkSubtitle(to location: CLLocation) -> String? {
        _ = walkVersion
        let walked = dayPlaces.compactMap { place in
            WalkingTimes.shared.walk(place.coordinate, location.coordinate).map { (place, $0) }
        }
        .min { $0.1.seconds < $1.1.seconds }
        if let walked {
            return Self.walkText(minutes: max(Int(walked.1.minutes.rounded()), 1), near: walked.0.name)
        }
        guard let nearest = dayPlaces.min(by: {
            $0.location.distance(from: location) < $1.location.distance(from: location)
        }) else { return nil }
        let minutes = max(Int((nearest.location.distance(from: location) * 1.3 / 80).rounded()), 1)
        return Self.walkText(minutes: minutes, near: nearest.name)
    }

    static func walkText(minutes: Int, near name: String) -> String {
        String(localized: "yürüyerek \(minutes) dk · \(name) yakınında")
    }

    private func spotRow(_ spot: GeoapifyService.Spot) -> some View {
        let saved = store.savedPlace(named: spot.name, near: spot.coordinate)
        return SpotRow(category: spot.category, title: spot.name, subtitle: walkSubtitle(to: spot.location) ?? "",
                       isAdded: isAdded(saved), general: general,
                       onAdd: { addSpot(spot, saved: saved) }) {
            LocationPhoto(name: spot.name, category: spot.category, city: city,
                          latitude: spot.latitude, longitude: spot.longitude,
                          size: 64, cornerRadius: 14)
        }
    }

    private var showAllLabel: some View {
        HStack(spacing: 6) {
            Text("Tümünü göster").textCase(.uppercase)
            Image(systemName: "chevron.down")
        }
        .font(Theme.font(13, .bold))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1.5))
    }

    private func nearbyRow(_ item: Recommender.Suggestion) -> some View {
        let place = item.place
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let saved = store.savedPlace(named: place.name, near: coordinate)
            ?? store.savedPlace(named: place.title, near: coordinate)
        return SpotRow(category: item.category, title: place.name,
                       subtitle: Self.walkText(minutes: item.walkingMinutes, near: item.anchorName),
                       isAdded: isAdded(saved), general: general,
                       onAdd: {
                           addedHere.insert(item.id)
                           addPopular(place, category: item.category, saved: saved)
                       }) {
            LocationPhoto(name: place.name, category: item.category, city: city,
                          latitude: place.latitude, longitude: place.longitude, englishTitle: place.title,
                          knownPhoto: place.thumbnailURL, size: 64, cornerRadius: 14)
        }
    }

    private func foodRow(_ result: GooglePlaces.SearchResult) -> some View {
        let category = result.category
        let saved = store.savedPlace(googleID: result.id, named: result.name, near: result.coordinate)
        let subtitle = walkSubtitle(to: CLLocation(latitude: result.latitude, longitude: result.longitude))
            ?? result.address
        return SpotRow(category: category, title: result.name, subtitle: subtitle,
                       isAdded: isAdded(saved), general: general,
                       onAdd: { add(result, saved: saved) },
                       onTap: { detailPlace = GooglePlaceRef(id: result.id, name: result.name, coordinate: result.coordinate) }) {
            LocationPhoto(name: result.name, category: category, city: city,
                          latitude: result.latitude, longitude: result.longitude,
                          size: 64, cornerRadius: 14)
        }
    }

    // MARK: - Satırlar

    private func resultRow(_ result: GooglePlaces.SearchResult) -> some View {
        let category = result.category
        let saved = store.savedPlace(googleID: result.id, named: result.name, near: result.coordinate)
        return SpotRow(category: category, title: result.name, subtitle: result.address,
                       isAdded: isAdded(saved), general: general,
                       onAdd: { add(result, saved: saved) },
                       onTap: { detailPlace = GooglePlaceRef(id: result.id, name: result.name, coordinate: result.coordinate) }) {
            LocationPhoto(name: result.name, category: category, city: city,
                          latitude: result.latitude, longitude: result.longitude,
                          size: 64, cornerRadius: 14)
        }
    }

    private func savedRow(_ place: Place) -> some View {
        SpotRow(category: place.category, title: place.name, subtitle: place.city,
                isAdded: isAdded(place), general: general,
                onAdd: { toggle(place) }) {
            LocationPhoto(name: place.name, category: place.category, city: place.city,
                          latitude: place.latitude, longitude: place.longitude,
                          englishTitle: place.wikipediaTitle, size: 64, cornerRadius: 14)
        }
    }

    private func popularRow(_ item: WikipediaService.PopularPlace) -> some View {
        let category = PlaceCategory.guess(name: item.title) ?? .sight
        let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        let saved = store.savedPlace(named: item.name, near: coordinate)
            ?? store.savedPlace(named: item.title, near: coordinate)
        return SpotRow(category: category, title: item.name, subtitle: city,
                       isAdded: isAdded(saved), general: general,
                       onAdd: { addPopular(item, category: category, saved: saved) }) {
            LocationPhoto(name: item.name, category: category, city: city,
                          latitude: item.latitude, longitude: item.longitude, englishTitle: item.title,
                          knownPhoto: item.thumbnailURL, size: 64, cornerRadius: 14)
        }
    }

    // MARK: - İşlemler

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            return
        }
        searching = true
        let found = await GooglePlaces.shared.search(text, near: center)
        searching = false
        if query.trimmingCharacters(in: .whitespacesAndNewlines) == text { results = found }
    }

    private func loadPopular() async {
        do {
            popular = try await WikipediaService.shared.popularPlaces(latitude: center.latitude, longitude: center.longitude)
            popularFailed = popular.isEmpty
        } catch {
            popularFailed = true
        }
    }

    /// Günün yerlerinin çevresindeki (1,5 km) popüler yerler, puanlanıp
    /// sıralanır; rotadaki yerler önerilmez. Güne yer eklenince yeniden
    /// hesaplanır (ilk açılış dışında kısa bir beklemeyle).
    private func loadNearby() async {
        let day = dayPlaces
        guard let stop, !day.isEmpty else {
            nearby = []
            nearbyFood = []
            nearbySpots = []
            return
        }
        if !nearby.isEmpty {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
        }
        loadingNearby = true
        defer { loadingNearby = false }
        let anchors = Recommender.anchors(day)
        let candidates = await withTaskGroup(of: [WikipediaService.PopularPlace].self) { group in
            for anchor in anchors {
                group.addTask {
                    (try? await WikipediaService.shared.popularPlaces(
                        latitude: anchor.latitude, longitude: anchor.longitude, limit: 60, radius: 1500)) ?? []
                }
            }
            var all: [WikipediaService.PopularPlace] = []
            for await found in group { all += found }
            return all
        }
        guard !Task.isCancelled else { return }
        let planned = store.trip(stop: stop).placeIDs.compactMap(store.place)
        let kept = addedHere
        let fresh = Recommender.rank(candidates, anchors: day, saved: store.places) { candidate in
            guard !kept.contains(candidate.id) else { return false }
            return planned.contains { Self.isSame($0, candidate) }
        }
        withAnimation(.snappy) { nearby = Recommender.merge(fresh, previous: nearby, keeping: kept) }

        // Yakındaki kafe, restoran ve park Geoapify'dan (Google kotası harcanmaz);
        // son eklenen iki yerin çevresi aranır.
        let needsFood = Recommender.needsFood(day)
        var spots: [GeoapifyService.Spot] = []
        if GeoapifyService.isConfigured {
            for anchor in anchors.prefix(2) {
                spots += await GeoapifyService.shared.nearby(
                    CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude), food: needsFood)
            }
            guard !Task.isCancelled else { return }
            spots = GeoapifyService.pick(spots, anchors: day) { spot in
                planned.contains {
                    $0.name.lowercased() == spot.name.lowercased() && $0.location.distance(from: spot.location) < 150
                }
            }
        }
        withAnimation(.snappy) { nearbySpots = spots }

        // Geoapify yoksa ya da yemek bulamadıysa Google'ın popüler restoran ve kafeleri.
        if needsFood, !spots.contains(where: { Self.isFood($0.category) }), GoogleAPI.isConfigured,
           let center = Recommender.center(of: day) {
            let food = await GooglePlaces.shared.popularFood(near: center)
            guard !Task.isCancelled else { return }
            let plannedIDs = Set(planned.compactMap(\.googlePlaceID))
            nearbyFood = Array(food.filter { !plannedIDs.contains($0.id) }.prefix(5))
        } else {
            nearbyFood = []
        }

        // Gerçek yürüme süreleri (Geoapify): her önerinin kuş uçuşu en yakın
        // yerine; karşı kıyıdaki gibi yürüyerek uzak öneriler çıkar.
        guard WalkingTimes.shared.isAvailable else { return }
        let points = nearby.map(\.coordinate) + spots.map(\.coordinate) + nearbyFood.map(\.coordinate)
        let near = Recommender.nearestAnchors(to: points, in: day)
        await WalkingTimes.shared.load(from: points, to: near.map(\.coordinate))
        guard !Task.isCancelled else { return }
        let walked = Recommender.applyingWalks(fresh, anchors: day) { WalkingTimes.shared.walk($0.coordinate, $1) }
        withAnimation(.snappy) {
            nearby = Recommender.merge(walked, previous: nearby, keeping: addedHere)
            walkVersion += 1
        }
    }

    /// Rotadaki yer bu öneriyle aynı mı: aynı Wikipedia sayfası ya da 200 m
    /// içinde aynı ad (Türkçe ya da İngilizce adıyla).
    nonisolated private static func isSame(_ place: Place, _ candidate: WikipediaService.PopularPlace) -> Bool {
        if place.wikipediaTitle == candidate.title { return true }
        let distance = place.location.distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
        guard distance < 200 else { return false }
        return [candidate.title, candidate.localTitle].compactMap { $0 }
            .contains { WikipediaService.matchesStrongly(title: $0, name: place.name) }
    }

    /// Satırdaki ✓: şehir planında "bu şehrin rotasında", genel aramada
    /// "kayıtlı". Başka bir koleksiyonda ya da gezide olması rotaya
    /// eklemeye engel değil.
    private func isAdded(_ saved: Place?) -> Bool {
        guard let saved else { return false }
        return general || isPlanned(saved)
    }

    /// Kayıtlı yerin "+" / ✓ düğmesi: genel aramada "Nereye eklensin?",
    /// şehir planında rotaya ekler ya da rotadan çıkarır.
    private func toggle(_ place: Place) {
        guard let stop else {
            destination = place
            return
        }
        if store.isPlanned(place, stop: stop) {
            store.removeFromPlan(place, stop: stop)
        } else {
            store.plan(place, stop: stop, day: day)
        }
    }

    private func add(_ result: GooglePlaces.SearchResult, saved: Place?) {
        if let saved { return toggle(saved) }
        let coordinate = result.coordinate
        Task {
            let city = await placeCity(coordinate)
            let place = Place(name: result.name, city: city, latitude: result.latitude,
                              longitude: result.longitude, category: result.category, source: .search,
                              googlePlaceID: result.id)
            save(place)
        }
    }

    private func addSpot(_ spot: GeoapifyService.Spot, saved: Place?) {
        if let saved { return toggle(saved) }
        Task {
            let city = await placeCity(spot.coordinate)
            save(Place(name: spot.name, city: city, latitude: spot.latitude, longitude: spot.longitude,
                       category: spot.category, source: .search))
        }
    }

    private func addPopular(_ item: WikipediaService.PopularPlace, category: PlaceCategory, saved: Place?) {
        if let saved { return toggle(saved) }
        let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        Task {
            let city = await placeCity(coordinate)
            let place = Place(name: item.name, city: city, latitude: item.latitude,
                              longitude: item.longitude, category: category, source: .search,
                              wikipediaTitle: item.title)
            save(place)
        }
    }

    /// Yeni yerin şehri: şehir planında o şehir; genel aramada konumdan
    /// (yakında kayıtlı bir şehir varsa o).
    private func placeCity(_ coordinate: CLLocationCoordinate2D) async -> String {
        guard general else { return city }
        return await importer.city(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                   knownCities: store.cities)
    }

    private func save(_ place: Place) {
        store.add(place, plan: stop, day: day)
        if general { destination = place }
    }
}

/// Listede bir yer: fotoğraf (köşesinde türün simgesi), türün renkli
/// etiketi, ad, şehir; sağda "+" (eklenince ✓). Satıra dokununca ayrıntı.
private struct SpotRow<Thumbnail: View>: View {
    let category: PlaceCategory
    let title: String
    let subtitle: String
    let isAdded: Bool
    /// Genel aramada ✓ "kayıtlı" demek; dokununca "Nereye eklensin?".
    var general = false
    let onAdd: () -> Void
    var onTap: (() -> Void)?
    @ViewBuilder let thumbnail: Thumbnail

    var body: some View {
        HStack(spacing: 14) {
            thumbnail.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(Theme.font(11, .bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(category.color)
                Text(title).font(Theme.font(17, .semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isAdded ? .white : Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(isAdded ? Theme.ink : .white, in: Circle())
                    .overlay(Circle().stroke(isAdded ? .clear : Theme.hairline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityTitle))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var accessibilityTitle: LocalizedStringKey {
        switch (general, isAdded) {
        case (true, true): "Kayıtlı, nereye ekleneceğini seç"
        case (true, false): "Kaydet"
        case (false, true): "Rotadan çıkar"
        case (false, false): "Rotaya ekle"
        }
    }
}

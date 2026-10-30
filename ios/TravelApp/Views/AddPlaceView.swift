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
                    }

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
                    ForEach(popular) { item in popularRow(item) }
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
        // Yazarken arar (her harfte değil, yazmaya ara verince; her arama
        // Google'ın ücretsiz kotasından düşer).
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await search()
        }
        .sheet(item: $detailPlace) { place in
            GooglePlaceSheet(place: place) { _ in detailPlace = nil }
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
            Text("Arama: Google Maps · Popüler yerler: Wikipedia")
                .font(Theme.font(12))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)
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
        Button { withAnimation { showAllSaved = true } } label: {
            HStack(spacing: 6) {
                Text("Tümünü göster").textCase(.uppercase)
                Image(systemName: "chevron.down")
            }
            .font(Theme.font(13, .bold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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

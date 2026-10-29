import MapKit
import SwiftUI

/// Yer ekle (Polarsteps'teki "Add a spot" gibi): arama (Apple Haritalar),
/// Kendi yerini oluştur, Fotoğrafla ekle, Kayıtlı yerler ve Popüler yerler
/// (Wikipedia okunma sayısı). Her satırda türün renkli etiketi ve "+";
/// "+" yeri rotada sağ üstte seçili güne ekler, haritada türünün
/// simgesiyle görünür.
struct AddPlaceView: View {
    let city: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var popular: [WikipediaService.PopularPlace] = []
    @State private var popularFailed = false
    @State private var showAllSaved = false
    @State private var detailItem: MKMapItem?
    @State private var showCustom = false
    @State private var showCamera = false
    /// Eklenen yerlerin günü (şehir planında bakılan gün).
    @State private var day: Int

    init(city: String, day: Int = 0) {
        self.city = city
        _day = State(initialValue: day)
    }

    private var center: CLLocationCoordinate2D {
        store.center(of: city) ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
    }

    /// Şehirdeki kayıtlar; rotada olmayanlar önce.
    private var saved: [Place] {
        store.places(in: city).sorted { !store.isPlanned($0) && store.isPlanned($1) }
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
                        ForEach(results, id: \.self) { item in resultRow(item) }
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
        .task { await loadPopular() }
        // Yazarken arar (her harfte değil, yazmaya ara verince).
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await search()
        }
        .appleDetailSheet(item: $detailItem)
        .sheet(isPresented: $showCustom) { CustomPlaceView(city: city, day: day) }
        .sheet(isPresented: $showCamera) { CameraAddView() }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
        .animation(.snappy, value: store.undoMessage)
    }

    // MARK: - Parçalar

    private var header: some View {
        ZStack {
            Text("Yer ekle").font(Theme.font(18, .bold))
            HStack {
                CircleIconButton(systemImage: "xmark") { dismiss() }
                    .accessibilityLabel(Text("Kapat"))
                Spacer()
                dayMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Hangi güne ekleneceği; tek günlük gezide görünmez.
    @ViewBuilder
    private var dayMenu: some View {
        let days = store.trip(for: city).days
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
            Text("Arama: Apple Haritalar · Popüler yerler: Wikipedia")
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

    private func resultRow(_ item: MKMapItem) -> some View {
        let coordinate = item.placemark.coordinate
        return SpotRow(category: PlaceCategory(item), title: item.name ?? "",
                       subtitle: item.placemark.locality ?? item.placemark.title ?? "",
                       isAdded: store.savedPlace(named: item.name ?? "", near: coordinate) != nil,
                       onAdd: { add(item) }, onTap: { detailItem = item }) {
            CategoryTile(category: PlaceCategory(item))
        }
    }

    private func savedRow(_ place: Place) -> some View {
        SpotRow(category: place.category, title: place.name, subtitle: place.city,
                isAdded: store.isPlanned(place), showsBadge: place.wikipediaTitle != nil,
                onAdd: { store.addToPlan([place.id], city: city, day: day) }) {
            if place.wikipediaTitle != nil {
                PlaceThumbnail(place: place, cornerRadius: 0)
            } else {
                CategoryTile(category: place.category)
            }
        }
    }

    private func popularRow(_ item: WikipediaService.PopularPlace) -> some View {
        let category = PlaceCategory.guess(name: item.title) ?? .sight
        let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        return SpotRow(category: category, title: item.title, subtitle: city,
                       isAdded: store.savedPlace(named: item.title, near: coordinate) != nil,
                       showsBadge: item.thumbnailURL != nil,
                       onAdd: { addPopular(item, category: category) }) {
            AsyncImage(url: item.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                CategoryTile(category: category)
            }
        }
    }

    // MARK: - İşlemler

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            return
        }
        searching = true
        let found = await PlaceSearch.search(text, in: MKCoordinateRegion(
            center: center, latitudinalMeters: 40_000, longitudinalMeters: 40_000))
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

    private func add(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        store.add(Place(name: item.name ?? String(localized: "Yer"), city: city,
                        latitude: c.latitude, longitude: c.longitude,
                        category: PlaceCategory(item), source: .search),
                  plan: true, day: day)
    }

    private func addPopular(_ item: WikipediaService.PopularPlace, category: PlaceCategory) {
        store.add(Place(name: item.title, city: city, latitude: item.latitude, longitude: item.longitude,
                        category: category, source: .search, wikipediaTitle: item.title),
                  plan: true, day: day)
    }
}

/// Listede bir yer: fotoğraf (köşesinde türün simgesi), türün renkli
/// etiketi, ad, şehir; sağda "+" (eklenince ✓). Satıra dokununca ayrıntı.
private struct SpotRow<Thumbnail: View>: View {
    let category: PlaceCategory
    let title: String
    let subtitle: String
    let isAdded: Bool
    var showsBadge = true
    let onAdd: () -> Void
    var onTap: (() -> Void)?
    @ViewBuilder let thumbnail: Thumbnail

    var body: some View {
        HStack(spacing: 14) {
            Theme.surface
                .overlay { thumbnail }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .bottomTrailing) {
                    if showsBadge {
                        CategoryPin(category: category, size: 22).offset(x: 5, y: 5)
                    }
                }
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
            .disabled(isAdded)
            .accessibilityLabel(Text(isAdded ? LocalizedStringKey("Rotada") : LocalizedStringKey("Rotaya ekle")))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

extension View {
    /// Apple Haritalar yer kartı: fotoğraflar, puanlar, çalışma saatleri.
    /// iOS 18'den eski telefonlarda yer Apple Haritalar'da açılır.
    @ViewBuilder
    func appleDetailSheet(item: Binding<MKMapItem?>) -> some View {
        if #available(iOS 18.0, *) {
            mapItemDetailSheet(item: item)
        } else {
            onChange(of: item.wrappedValue) { _, newItem in
                guard let newItem else { return }
                newItem.openInMaps()
                item.wrappedValue = nil
            }
        }
    }
}

import MapKit
import SwiftUI

// MARK: - Fotoğraf

/// Koleksiyondaki şeyin fotoğrafı: ülke için Wikivoyage manzarası, şehir
/// için Wikipedia/Wikivoyage, yer için yerin kendi fotoğrafı.
struct CollectionItemPhoto: View {
    let item: CollectionItem
    @State private var url: URL?

    var body: some View {
        RemoteImage(url: url)
            .overlay {
                if url == nil { placeholder }
            }
            .task(id: item.key) { url = await Self.photo(for: item) }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch item.kind {
        case .country:
            Text(item.countryCode.map(Country.flag) ?? "🌍").font(.system(size: 34))
        case .city:
            Image(systemName: "building.2").font(.system(size: 22)).foregroundStyle(Theme.muted)
        case .place:
            CategoryTile(category: item.category ?? .sight)
        }
    }

    static func photo(for item: CollectionItem) async -> URL? {
        let title = item.englishTitle ?? item.name
        switch item.kind {
        case .country:
            if let banner = await DiscoverService.shared.info([title], from: .wikivoyage)[title]?.photo { return banner }
            return await DiscoverService.shared.photo(title)
        case .city:
            return await DiscoverService.shared.photo(title)
        case .place:
            guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
            return await WikipediaService.shared.photo(name: item.name, city: "", latitude: latitude,
                                                       longitude: longitude, englishTitle: item.englishTitle)
        }
    }
}

/// Koleksiyonun kapağı: ilk şeyin fotoğrafı, boşsa renk ve simge.
struct CollectionCover: View {
    let collection: PlaceCollection

    var body: some View {
        Color(hex: PlaceCollection.colors[collection.color % PlaceCollection.colors.count]).opacity(0.55)
            .overlay {
                if let first = collection.items.first {
                    CollectionItemPhoto(item: first)
                } else {
                    Text(collection.emoji).font(.system(size: 34))
                }
            }
            .clipped()
    }
}

// MARK: - Kaydet düğmesi

/// Kartların sağ üstündeki kaydet düğmesi (yer işareti): dokununca
/// "Koleksiyona kaydet" penceresi açılır. Bir koleksiyondaysa dolu.
struct CollectButton: View {
    let item: CollectionItem
    var size: CGFloat = 34
    /// Yalnızca geliştirme sürümünde `-screen saveTo` ile kendiliğinden açılan düğme.
    var opensForScreenshot = false
    @EnvironmentObject private var store: AppStore
    @State private var showSave = false

    var body: some View {
        Button { showSave = true } label: {
            Image(systemName: store.isCollected(item) ? "bookmark.fill" : "bookmark")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(.white.opacity(0.92), in: Circle())
                .softShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Koleksiyona kaydet"))
        .sheet(isPresented: $showSave) { SaveToCollectionSheet(item: item) }
        .task {
            #if DEBUG
            // `-screen saveTo`: ülke sayfasında "Koleksiyona kaydet" açık (ekran görüntüsü için).
            if opensForScreenshot, !Self.openedLaunchScreen,
               UserDefaults.standard.string(forKey: "screen") == "saveTo" {
                Self.openedLaunchScreen = true
                try? await Task.sleep(for: .seconds(1))
                showSave = true
            }
            #endif
        }
    }

    #if DEBUG
    private static var openedLaunchScreen = false
    #endif
}

// MARK: - Koleksiyona kaydet

/// "Koleksiyona kaydet" (Polarsteps "Save to collection"): koleksiyonlar
/// listesi, dokununca ekler ya da çıkarır; "Yeni koleksiyon" ile adı sorulup
/// oluşturulur ve içine eklenir.
struct SaveToCollectionSheet: View {
    let item: CollectionItem
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CollectionItemPhoto(item: item)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Koleksiyona kaydet").font(Theme.font(17, .bold))
                    Text(item.displayName).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                CircleIconButton(systemImage: "xmark") { dismiss() }
                    .accessibilityLabel(Text("Kapat"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            HStack {
                Text("Koleksiyonlar").font(Theme.font(20, .bold))
                Spacer()
                Button("Yeni koleksiyon") { showNew = true }
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    if store.collections.isEmpty {
                        Text("Henüz koleksiyonun yok. \"Yeni koleksiyon\" ile ilkini oluştur.")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                    ForEach(store.collections) { collection in
                        Button { store.toggle(item, in: collection.id) } label: { row(collection) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(.white)
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.sheetRadius)
        .sheet(isPresented: $showNew) {
            CollectionEditor(item: item)
        }
    }

    private func row(_ collection: PlaceCollection) -> some View {
        let isIn = store.contains(item, in: collection.id)
        return HStack(spacing: 14) {
            CollectionCover(collection: collection)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name).font(Theme.font(16, .semibold)).lineLimit(1)
                Text("\(collection.items.count) öğe").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isIn ? Theme.ink : Theme.hairline)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isIn ? .isSelected : [])
    }
}

// MARK: - Yeni koleksiyon / düzenle

/// Yeni koleksiyon (Polarsteps "New collection"): simge, renk ve ad (en çok
/// 50 harf); ✓ ile oluşturulur. Var olan koleksiyonu düzenlemek için de.
struct CollectionEditor: View {
    /// Düzenlenen koleksiyon; nil ise yeni.
    var editing: PlaceCollection?
    /// Yeni koleksiyon oluşunca içine eklenecek şey.
    var item: CollectionItem?
    var onCreate: (UUID) -> Void = { _ in }
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = PlaceCollection.emojis[0]
    @State private var color = 0
    @FocusState private var nameFocused: Bool

    private static let maxLength = 50
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(editing == nil ? LocalizedStringKey("Yeni koleksiyon") : LocalizedStringKey("Koleksiyonu düzenle"))
                    .font(Theme.font(18, .bold))
                HStack {
                    CircleIconButton(systemImage: "xmark") { dismiss() }
                        .accessibilityLabel(Text("Kapat"))
                    Spacer()
                    Button(action: save) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(trimmed.isEmpty ? Theme.hairline : Theme.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty)
                    .accessibilityLabel(Text("Kaydet"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Text(emoji)
                .font(.system(size: 56))
                .frame(width: 112, height: 112)
                .background(Color(hex: PlaceCollection.colors[color]).opacity(0.55), in: Circle())
                .padding(.top, 20)

            HStack(spacing: 8) {
                ForEach(PlaceCollection.emojis, id: \.self) { option in
                    Button { emoji = option } label: {
                        Text(option)
                            .font(.system(size: 22))
                            .frame(width: 38, height: 38)
                            .background(emoji == option ? Theme.surface : .clear, in: Circle())
                            .overlay(Circle().stroke(emoji == option ? Theme.ink : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            HStack(spacing: 14) {
                ForEach(PlaceCollection.colors.indices, id: \.self) { index in
                    Button { color = index } label: {
                        Circle()
                            .fill(Color(hex: PlaceCollection.colors[index]))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: color == index ? 2.5 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Renk \(index + 1)"))
                }
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Koleksiyon adı").font(Theme.font(12)).foregroundStyle(Theme.muted)
                HStack {
                    TextField("", text: $name)
                        .font(Theme.font(17))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: name) { _, value in
                            if value.count > Self.maxLength { name = String(value.prefix(Self.maxLength)) }
                        }
                    Text(verbatim: "\(Self.maxLength - name.count)")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.accent.opacity(0.6), lineWidth: 2))
            .padding(.horizontal, 16)
            .padding(.top, 26)

            Spacer()
        }
        .background(.white)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.sheetRadius)
        .onAppear {
            if let editing {
                name = editing.name
                emoji = editing.emoji
                color = editing.color % PlaceCollection.colors.count
            }
            nameFocused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        if let editing {
            store.editCollection(editing.id, name: trimmed, emoji: emoji, color: color)
        } else {
            let id = store.createCollection(name: trimmed, emoji: emoji, color: color, with: item)
            onCreate(id)
        }
        dismiss()
    }
}

// MARK: - Koleksiyonlar listesi (Keşfet → Koleksiyonlar)

/// Keşfet panelindeki "Koleksiyonlar": iki sütun kapaklar ve "Yeni koleksiyon".
struct CollectionsSection: View {
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @State private var showNew = false
    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Koleksiyonlar").font(Theme.font(22, .bold))
                Spacer()
                Button("Yeni koleksiyon") { showNew = true }
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)

            if store.collections.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                    ForEach(store.collections) { collection in
                        Button { path.append(.collection(collection.id)) } label: {
                            CollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            #if DEBUG
            // `-screen newCollection`: yeni koleksiyon penceresi açık (ekran görüntüsü için).
            if !Self.openedLaunchScreen, UserDefaults.standard.string(forKey: "screen") == "newCollection" {
                Self.openedLaunchScreen = true
                showNew = true
            }
            #endif
        }
        .sheet(isPresented: $showNew) {
            CollectionEditor { id in
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    path.append(.collection(id))
                }
            }
        }
    }

    private var emptyState: some View {
        Button { showNew = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.muted)
                Text("Sonra dönmek istediğin ülke, şehir ve yerleri koleksiyonlarda topla.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Text("Yeni koleksiyon").font(Theme.font(15, .semibold)).foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .buttonStyle(.plain)
    }
}

/// Koleksiyon kartı: üst üste duran iki kart gibi kapak, ortada simge,
/// altta ad ve öğe sayısı.
struct CollectionCard: View {
    let collection: PlaceCollection

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: PlaceCollection.colors[collection.color % PlaceCollection.colors.count]).opacity(0.7))
                    .rotationEffect(.degrees(-7))
                    .padding(6)
                CollectionCover(collection: collection)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .rotationEffect(.degrees(4))
                    .padding(6)
                    .softShadow()
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                Text(collection.emoji)
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Theme.hairlineLight))
                    .offset(y: 8)
            }
            Text(collection.name)
                .font(Theme.font(16, .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 8)
            Text("\(collection.items.count) öğe")
                .font(Theme.font(11, .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Koleksiyon

/// Koleksiyonun içi (Polarsteps "Deneme koleksiyonu"): haritada içindekiler,
/// üstünde kayan panel; Tümü / Şehirler / Yerler, iki sütun fotoğraflı
/// kartlar, "+" ile yer ya da şehir ekleme; "…" menüsünde düzenle ve sil.
struct CollectionDetailView: View {
    let collectionID: UUID
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Filter = .all
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 400
    @State private var position: MapCameraPosition = .automatic
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var addSheet: AddKind?

    enum Filter { case all, destinations, spots }

    enum AddKind: String, Identifiable {
        case place, destination
        var id: String { rawValue }
    }

    private var collection: PlaceCollection? { store.collection(collectionID) }

    private var items: [CollectionItem] {
        guard let collection else { return [] }
        switch filter {
        case .all: return collection.items
        case .destinations: return collection.destinations
        case .spots: return collection.spots
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map

            if let collection {
                // En üstte geri düğmesi görünür kalsın diye ekranın %92'si.
                DraggablePanel(stops: [.height(170), .fraction(0.55), .fraction(0.92)], selection: $panelStop,
                               onSettle: { panelHeight = $0 }) {
                    header(collection)
                } content: {
                    grid
                }
                .overlay(alignment: .bottomTrailing) { addButton }
            }

            CircleIconButton(systemImage: "chevron.left") { dismiss() }
                .accessibilityLabel(Text("Geri"))
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 24) }
        .animation(.snappy, value: store.undoMessage)
        .sheet(isPresented: $showEdit) {
            if let collection { CollectionEditor(editing: collection) }
        }
        .sheet(item: $addSheet) { kind in
            switch kind {
            case .place: CollectionAddPlaceSheet(collectionID: collectionID)
            case .destination: CollectionAddDestinationSheet(collectionID: collectionID)
            }
        }
        .confirmationDialog("Koleksiyon silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Koleksiyonu sil", role: .destructive) {
                dismiss()
                store.deleteCollection(collectionID)
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .onAppear(perform: fitMap)
        .onChange(of: collection?.items.count) { fitMap() }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(items.filter { $0.coordinate != nil }) { item in
                if let coordinate = item.coordinate {
                    Annotation(item.displayName, coordinate: coordinate, anchor: .center) {
                        Button { open(item) } label: { pin(item) }
                            .buttonStyle(.plain)
                    }
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .safeAreaPadding(.top, 52)
        .safeAreaPadding(.bottom, panelHeight + 20)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func pin(_ item: CollectionItem) -> some View {
        switch item.kind {
        case .place:
            CategoryPin(category: item.category ?? .sight, size: 30)
        case .city, .country:
            CollectionItemPhoto(item: item)
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .softShadow()
        }
    }

    private func header(_ collection: PlaceCollection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(collection.name).font(Theme.font(24, .bold)).lineLimit(1)
                Spacer()
                Menu {
                    Button { showEdit = true } label: { Label("Düzenle", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Koleksiyonu sil", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel(Text("Koleksiyon menüsü"))
            }
            HStack(spacing: 8) {
                chip("Tümü", count: collection.items.count, value: .all)
                chip("Ülke ve şehirler", count: collection.destinations.count, value: .destinations)
                chip("Yerler", count: collection.spots.count, value: .spots)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func chip(_ title: LocalizedStringKey, count: Int, value: Filter) -> some View {
        let selected = filter == value
        return Button { withAnimation(.snappy) { filter = value } } label: {
            HStack(spacing: 6) {
                Text(title).font(Theme.font(14, .semibold))
                Text("\(count)")
                    .font(Theme.font(11, .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selected ? .white.opacity(0.25) : Theme.surface, in: Capsule())
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Theme.ink : .white, in: Capsule())
            .overlay(Capsule().stroke(selected ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var grid: some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark").font(.system(size: 26)).foregroundStyle(Theme.muted)
                Text("Sonra dönmek istediğin her şeyi kaydet. Sağ alttaki + ile yer ya da şehir ekle.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.vertical, 30)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                ForEach(items) { item in
                    // Kartın içinde kaydet düğmesi var; kartın kendisi dokunulur.
                    card(item)
                        .contentShape(Rectangle())
                        .onTapGesture { open(item) }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 140)
        }
    }

    private func card(_ item: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CollectionItemPhoto(item: item)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(alignment: .topTrailing) {
                    Button { store.removeItem(item.id, from: collectionID) } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.92), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel(Text("Koleksiyondan çıkar"))
                }
            label(item).padding(.top, 4)
            Text(item.displayName).font(Theme.font(16, .bold)).lineLimit(1)
        }
    }

    @ViewBuilder
    private func label(_ item: CollectionItem) -> some View {
        HStack(spacing: 4) {
            switch item.kind {
            case .place:
                Image(systemName: (item.category ?? .sight).symbol)
                Text((item.category ?? .sight).title)
            case .city:
                Image(systemName: "building.2.fill")
                Text("Şehir")
            case .country:
                Text(item.countryCode.map(Country.flag) ?? "")
                Text("Ülke")
            }
        }
        .font(Theme.font(11, .bold))
        .textCase(.uppercase)
        .tracking(0.5)
        .foregroundStyle(item.kind == .place ? (item.category ?? .sight).color : Theme.accent)
    }

    private var addButton: some View {
        Menu {
            Button { addSheet = .place } label: { Label("Yer", systemImage: "mappin.and.ellipse") }
            Button { addSheet = .destination } label: { Label("Şehir ya da ülke", systemImage: "globe.europe.africa") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.ink, in: Circle())
                .softShadow()
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Ekle"))
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    private func open(_ item: CollectionItem) {
        switch item.kind {
        case .country:
            if let code = item.countryCode { path.append(.country(code)) }
        case .city:
            guard let latitude = item.latitude, let longitude = item.longitude else { return }
            path.append(.cityGuide(CityChoice(name: item.name, countryCode: item.countryCode, latitude: latitude,
                                              longitude: longitude, englishTitle: item.englishTitle)))
        case .place:
            if let id = item.placeID, store.place(id) != nil { path.append(.place(id)) }
        }
    }

    private func fitMap() {
        let coordinates = (collection?.items ?? []).compactMap(\.coordinate)
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1, let only = coordinates.first {
            position = .camera(MapCamera(centerCoordinate: only, distance: 60_000))
        } else if let region = MKCoordinateRegion(fitting: coordinates, padding: 1.4) {
            position = .region(region)
        }
    }
}

// MARK: - Koleksiyona ekle

/// Koleksiyona yer ekle (Polarsteps "Add spot"): Apple Haritalar araması,
/// yerin fotoğrafı ve türüyle; dokununca Kayıtlarım'a ve koleksiyona eklenir.
struct CollectionAddPlaceSheet: View {
    let collectionID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Yer ekle") { dismiss() }
            SearchField(text: $query, prompt: "Yer, restoran ya da otel ara", isSearching: searching, focus: $focused)
                .padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(results, id: \.self) { item in row(item) }
                    if !query.isEmpty && !searching && results.isEmpty {
                        Text("Sonuç bulunamadı.").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(.white)
        .foregroundStyle(Theme.ink)
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
        .animation(.snappy, value: store.undoMessage)
        .onAppear { focused = true }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                results = []
                return
            }
            searching = true
            let found = await PlaceSearch.search(text, in: nil)
            searching = false
            if !Task.isCancelled { results = found }
        }
    }

    private func row(_ item: MKMapItem) -> some View {
        let coordinate = item.placemark.coordinate
        let category = PlaceCategory(item)
        let saved = store.savedPlace(named: item.name ?? "", near: coordinate)
        let isIn = saved.map { store.contains(.place($0), in: collectionID) } ?? false
        return Button { add(item, category: category) } label: {
            HStack(spacing: 14) {
                LocationPhoto(name: item.name ?? "", category: category, city: item.placemark.locality ?? "",
                              latitude: coordinate.latitude, longitude: coordinate.longitude, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(Theme.font(11, .bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(category.color)
                    Text(item.name ?? "").font(Theme.font(16, .semibold)).lineLimit(1)
                    Text([item.placemark.locality, item.placemark.country].compactMap { $0 }.joined(separator: ", "))
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: isIn ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isIn ? Theme.ink : Theme.muted)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add(_ item: MKMapItem, category: PlaceCategory) {
        let coordinate = item.placemark.coordinate
        var place = store.savedPlace(named: item.name ?? "", near: coordinate)
        if place == nil {
            let new = Place(name: item.name ?? String(localized: "Yer"),
                            city: item.placemark.locality ?? item.placemark.administrativeArea
                                ?? item.placemark.country ?? String(localized: "Diğer"),
                            latitude: coordinate.latitude, longitude: coordinate.longitude,
                            category: category, source: .search)
            store.add(new, plan: false)
            place = new
        }
        if let place { store.toggle(.place(place), in: collectionID) }
    }
}

/// Koleksiyona şehir ya da ülke ekle: arama (ülkeler uygulamadaki listeden,
/// şehirler Apple Haritalar'dan); dokununca eklenir ya da çıkarılır.
struct CollectionAddDestinationSheet: View {
    let collectionID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = CitySearch()
    @State private var resolving: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Şehir ya da ülke ekle") { dismiss() }
            SearchField(text: $search.query, prompt: "Şehir ya da ülke ara", isSearching: search.isSearching, focus: $focused)
                .padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(search.countries) { country in
                        let item = CollectionItem.country(country)
                        Button { store.toggle(item, in: collectionID) } label: {
                            ResultRow(title: country.name, subtitle: Continent.of(country.code)?.name ?? "") {
                                CollectionItemPhoto(item: item)
                            } trailing: {
                                mark(store.contains(item, in: collectionID))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(search.cities, id: \.self) { completion in
                        Button { Task { await add(completion) } } label: {
                            ResultRow(title: completion.title, subtitle: completion.subtitle) {
                                CityPhoto(name: completion.title.components(separatedBy: ",").first ?? completion.title)
                            } trailing: {
                                if resolving == completion.title {
                                    ProgressView()
                                } else {
                                    mark(isAdded(completion))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(.white)
        .foregroundStyle(Theme.ink)
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
        .animation(.snappy, value: store.undoMessage)
        .onAppear { focused = true }
    }

    private func mark(_ isIn: Bool) -> some View {
        Image(systemName: isIn ? "checkmark.circle.fill" : "plus.circle")
            .font(.system(size: 24))
            .foregroundStyle(isIn ? Theme.ink : Theme.muted)
    }

    private func isAdded(_ completion: MKLocalSearchCompletion) -> Bool {
        let name = completion.title.components(separatedBy: ",").first ?? completion.title
        return store.collection(collectionID)?.items.contains { $0.kind == .city && $0.name == name } ?? false
    }

    private func add(_ completion: MKLocalSearchCompletion) async {
        guard resolving == nil else { return }
        resolving = completion.title
        let choice = await CitySearch.resolve(completion)
        resolving = nil
        if let choice { store.toggle(.city(choice), in: collectionID) }
    }
}

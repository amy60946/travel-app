import MapKit
import SwiftUI

/// Haritadaki yer pini: beyaz hap içinde türün renkli simgesi + ad;
/// aktifse siyah.
struct PlacePin: View {
    let place: Place
    var isActive = false

    var body: some View {
        HStack(spacing: 6) {
            CategoryIcon(category: place.category, size: 20)
            Text(place.name)
                .font(Theme.font(12, .semibold))
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .foregroundStyle(isActive ? .white : Theme.ink)
        .background(isActive ? Theme.ink : .white, in: Capsule())
        .softShadow()
    }
}

/// Planda gün numarası: siyah daire.
struct DayBadge: View {
    let number: Int
    var size: CGFloat = 26

    var body: some View {
        Text("\(number)")
            .font(Theme.font(size * 0.5, .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.ink, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .softShadow()
    }
}

/// Kiremit ana düğme.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { PrimaryLabel(title: title, systemImage: systemImage) }
            .buttonStyle(.plain)
    }
}

/// Ana düğmenin görünümü (menü düğmelerinde de kullanılır).
struct PrimaryLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
            if showsChevron { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
        }
        .font(Theme.font(16, .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
    }
}

/// Beyaz, çerçeveli ikincil düğme.
struct SecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { SecondaryLabel(title: title, systemImage: systemImage) }
            .buttonStyle(.plain)
    }
}

/// İkincil düğmenin görünümü (menü düğmelerinde de kullanılır).
struct SecondaryLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
            if showsChevron { Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
        }
        .font(Theme.font(14, .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.hairline))
    }
}

/// Yerin rotadaki günü tek düğmede. Rotadaysa "2. gün ⌄": menüden başka
/// güne taşınır ya da rotadan çıkarılır. Değilse "Rotaya ekle"; birden çok
/// gün varsa hangi güne ekleneceği sorulur. Şehir planı dışında (ana
/// harita, koleksiyon) yerin bulunduğu gezi kullanılır; hiçbir gezide
/// değilse "Nereye eklensin?" penceresi açılır.
struct PlanDayButton: View {
    let place: Place
    /// Bakılan gezi şehri (şehir planından açılınca).
    var stop: UUID?
    @EnvironmentObject private var store: AppStore
    @State private var choosesTrip = false

    private var slot: AppStore.PlanSlot? {
        guard let stop else { return store.plans(containing: place).first }
        guard let ref = store.stop(stop), let day = store.dayIndex(of: place, stop: stop) else { return nil }
        return AppStore.PlanSlot(ref: ref, day: day)
    }

    var body: some View {
        // Pencere düğmenin dışında: yer geziye eklenince düğme değişse de açık kalır.
        button.sheet(isPresented: $choosesTrip) { SaveToCollectionSheet(item: .place(place), place: place) }
    }

    @ViewBuilder
    private var button: some View {
        if let slot {
            let days = store.trip(stop: slot.ref.id).days
            Menu {
                Picker("Gün", selection: Binding(get: { slot.day },
                                                 set: { store.move(place, toDay: $0, stop: slot.ref.id) })) {
                    ForEach(0..<days, id: \.self) { Text("\($0 + 1). gün").tag($0) }
                }
                .pickerStyle(.inline)
                Button(role: .destructive) { store.removeFromPlan(place, stop: slot.ref.id) } label: {
                    Label("Rotadan çıkar", systemImage: "minus.circle")
                }
            } label: {
                SecondaryLabel(title: "\(slot.day + 1). gün", systemImage: "calendar", showsChevron: true)
            }
            .menuOrder(.fixed)
            .accessibilityHint(Text("Günü değiştir"))
        } else if let stop, store.trip(stop: stop).days > 1 {
            Menu {
                ForEach(0..<store.trip(stop: stop).days, id: \.self) { day in
                    Button("\(day + 1). güne ekle") { store.plan(place, stop: stop, day: day) }
                }
            } label: {
                PrimaryLabel(title: "Rotaya ekle", systemImage: "plus")
            }
            .menuOrder(.fixed)
        } else {
            PrimaryButton(title: "Rotaya ekle", systemImage: "plus") {
                if let stop {
                    store.plan(place, stop: stop, day: 0)
                } else {
                    choosesTrip = true
                }
            }
        }
    }
}

/// Süzme hapı (Tümü / Instagram / ...).
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(14, .semibold))
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.ink : .white, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
    }
}

/// Yuvarlak beyaz harita düğmesi (geri, kapat).
struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(.white, in: Circle())
                .softShadow()
        }
        .buttonStyle(.plain)
    }
}

/// Yerin fotoğrafı: Wikipedia sayfasından, yoksa yakında çekilmiş bir
/// fotoğraf (Wikimedia Commons); bulunamazsa tür ikonu.
struct PlaceThumbnail: View {
    let place: Place
    var cornerRadius: CGFloat = Theme.cardRadius
    @State private var url: URL?

    var body: some View {
        // Zemin verilen boyutu alır, fotoğraf onun üstüne sığdırılıp kırpılır;
        // böylece geniş fotoğraf hücresinden taşmaz.
        Theme.surface
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Theme.surface
                    }
                } else {
                    Image(systemName: place.category.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: "\(place.id)|\(place.wikipediaTitle ?? "")") {
            url = await WikipediaService.shared.photo(name: place.name, city: place.city,
                                                      latitude: place.latitude, longitude: place.longitude,
                                                      englishTitle: place.wikipediaTitle)
        }
    }
}

/// Kaynak etiketi (Instagram, TikTok, ...).
struct SourceTag: View {
    let source: PlaceSource

    var body: some View {
        Text(source.title)
            .font(Theme.font(11, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.92), in: Capsule())
    }
}

/// "Tahmini" etiketi: yer kendiliğinden bulundu, emin değiliz.
struct EstimatedTag: View {
    var body: some View {
        Label("Tahmini", systemImage: "questionmark.circle")
            .font(Theme.font(11, .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.surface, in: Capsule())
    }
}

/// "Dinle" kartı: yerin yazısını Türkçe iPhone sesiyle okur. Çalarken kart
/// oynatıcıya dönüşür: 10 sn geri, duraklat, 10 sn ileri ve dokunulunca
/// oraya saran çizgi. Bu yerin sayfasında alttaki çubuk ayrıca görünmez.
struct ListenCard: View {
    let title: String
    let summary: WikipediaService.Summary?
    @ObservedObject private var narrator = Narrator.shared

    var body: some View {
        let isCurrent = narrator.currentTitle == title
        Group {
            if isCurrent { playing } else { idle }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .animation(.snappy, value: isCurrent)
    }

    private var idle: some View {
        Button {
            if let summary { narrator.speak(summary.extract, title: title, language: summary.language) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.ink, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dinle").font(Theme.headline)
                    Text(subtitle).font(Theme.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(summary == nil)
        .opacity(summary == nil ? 0.5 : 1)
    }

    private var subtitle: String {
        guard let summary else { return String(localized: "Anlatım hazırlanıyor") }
        let minutes = max(1, Int((Narrator.estimatedDuration(of: summary.extract) / 60).rounded()))
        return summary.language == "tr"
            ? String(localized: "\(minutes) dk · Türkçe anlatım")
            : String(localized: "\(minutes) dk · İngilizce anlatım")
    }

    private var playing: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(narrator.isPaused ? LocalizedStringKey("Duraklatıldı") : LocalizedStringKey("Dinleniyor"))
                    .font(Theme.headline)
                Spacer(minLength: 0)
                NarrationControls()
            }
            NarrationTimeline()
        }
    }
}

/// 10 sn geri, oynat / duraklat, 10 sn ileri.
struct NarrationControls: View {
    @ObservedObject private var narrator = Narrator.shared

    var body: some View {
        HStack(spacing: 2) {
            skip("gobackward.10", seconds: -10, label: "10 saniye geri")
            Button { narrator.togglePause() } label: {
                Image(systemName: narrator.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(narrator.isPaused ? LocalizedStringKey("Oynat") : LocalizedStringKey("Duraklat")))
            skip("goforward.10", seconds: 10, label: "10 saniye ileri")
        }
    }

    private func skip(_ symbol: String, seconds: Double, label: LocalizedStringKey) -> some View {
        Button { narrator.skip(by: seconds) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Anlatımın ilerleme çizgisi; dokununca ya da sürükleyince o yere sarar.
/// Altında geçen ve kalan süre.
struct NarrationTimeline: View {
    var showsTimes = true
    @ObservedObject private var narrator = Narrator.shared
    /// Sürüklerken parmağın olduğu yer (0...1).
    @State private var dragFraction: Double?

    var body: some View {
        let fraction = dragFraction ?? narrator.progress
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(6, width * CGFloat(fraction)))
                }
                .frame(height: dragFraction == nil ? 4 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = min(max(Double(value.location.x / width), 0), 1)
                        }
                        .onEnded { value in
                            narrator.seek(to: min(max(Double(value.location.x / width), 0), 1))
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 20)
            if showsTimes {
                HStack {
                    Text(verbatim: Narrator.clock(fraction * narrator.duration))
                    Spacer()
                    Text(verbatim: "-" + Narrator.clock((1 - fraction) * narrator.duration))
                }
                .font(Theme.font(11, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
            }
        }
        .animation(.snappy(duration: 0.15), value: dragFraction == nil)
        .accessibilityElement()
        .accessibilityLabel(Text("Anlatımın ilerlemesi"))
        .accessibilityValue(Text(verbatim: "\(Narrator.clock(narrator.elapsed)) / \(Narrator.clock(narrator.duration))"))
        .accessibilityAdjustableAction { direction in
            narrator.skip(by: direction == .increment ? 10 : -10)
        }
    }
}

extension View {
    /// Sayfanın altına anlatım çubuğunu koyar; sayfa içeriği (ve sağ alttaki
    /// düğmeler) çubuğun üstünde kalır. NavigationStack'e bir kez koymak
    /// açılan sayfaları itmediği için her sayfaya ayrı konur. `hiding`: o
    /// yer kendi sayfasında çalıyorsa çubuk gösterilmez (kart oynatıcıdır).
    func narrationBarInset(hiding title: String? = nil) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { NarrationBar(hiddenTitle: title) }
    }
}

/// Anlatım çalarken ekranın altında duran sade çubuk: ad ve süre, 10 sn
/// geri, oynat / duraklat, 10 sn ileri, kapat; altta sarılabilen çizgi.
/// Sayfa değişse de görünür kalır; aşağı itince kapanır.
struct NarrationBar: View {
    var hiddenTitle: String?
    @ObservedObject private var narrator = Narrator.shared

    var body: some View {
        ZStack {
            if let title = narrator.currentTitle, title != hiddenTitle { bar(title) }
        }
        .animation(.snappy, value: narrator.currentTitle)
    }

    private func bar(_ title: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.font(15, .semibold))
                        .lineLimit(1)
                    Text(verbatim: "\(Narrator.clock(narrator.elapsed)) / \(Narrator.clock(narrator.duration))")
                        .font(Theme.font(12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                NarrationControls()
                Button { narrator.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Anlatımı kapat"))
            }
            NarrationTimeline(showsTimes: false)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .softShadow()
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height > 50, abs(value.translation.width) < 60 { narrator.stop() }
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Yerin liste fotoğrafı (Polarsteps "Add a spot" gibi): yerin gerçek
/// fotoğrafı, sağ alt köşesinde türün küçük kare simgesi; fotoğraf yoksa
/// türün renginde kare.
struct PlaceRowThumbnail: View {
    let place: Place
    var size: CGFloat = 56

    var body: some View {
        LocationPhoto(name: place.name, category: place.category, city: place.city,
                      latitude: place.latitude, longitude: place.longitude,
                      englishTitle: place.wikipediaTitle, size: size)
    }
}

/// Bir yerin gerçek fotoğrafı (Wikipedia ya da yakında çekilmiş), sağ alt
/// köşesinde türün küçük kare simgesi; bulunamazsa türün renginde kare.
/// Kayıtlı olmayan yerler (arama sonuçları) için de kullanılır.
struct LocationPhoto: View {
    let name: String
    let category: PlaceCategory
    var city = ""
    let latitude: Double
    let longitude: Double
    var englishTitle: String?
    /// Zaten bilinen fotoğraf (ör. popüler yerler listesinden); varsa aranmaz.
    var knownPhoto: URL?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12
    @State private var url: URL?

    var body: some View {
        Theme.surface
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Theme.surface
                    }
                } else {
                    CategoryTile(category: category)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .bottomTrailing) {
                if url != nil {
                    CategoryBadge(category: category, size: max(18, size * 0.36)).offset(x: 4, y: 4)
                }
            }
            .task(id: "\(name)|\(englishTitle ?? "")|\(latitude)|\(longitude)") {
                if let knownPhoto {
                    url = knownPhoto
                    return
                }
                url = await WikipediaService.shared.photo(name: name, city: city, latitude: latitude,
                                                          longitude: longitude, englishTitle: englishTitle)
            }
    }
}

/// Fotoğrafın köşesindeki tür simgesi: türün renginde küçük kare, beyaz çerçeve.
struct CategoryBadge: View {
    let category: PlaceCategory
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color, in: RoundedRectangle(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).stroke(.white, lineWidth: 1.5))
            .softShadow()
            .accessibilityLabel(Text(category.title))
    }
}

/// Fotoğrafı olmayan yer: türün açık renginde kare, ortada türün simgesi.
struct CategoryTile: View {
    let category: PlaceCategory

    var body: some View {
        category.color.opacity(0.14)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(category.color)
            }
    }
}

/// Anlatımın kaynağı; İngilizceden çevrildiyse bunu da söyler.
struct WikipediaCredit: View {
    let summary: WikipediaService.Summary

    var body: some View {
        if let url = summary.pageURL {
            Link(destination: url) {
                Text(summary.translatedFrom == nil
                     ? LocalizedStringKey("Kaynak: Wikipedia (CC BY-SA)")
                     : LocalizedStringKey("Kaynak: İngilizce Wikipedia (CC BY-SA), Türkçeye çevrildi"))
                    .font(Theme.caption)
                    .underline()
            }
            .foregroundStyle(Theme.muted)
        }
    }
}

/// Alttan çıkan "Geri al" bildirimi.
struct UndoToast: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if let message = store.undoMessage {
            HStack {
                Text(message)
                    .font(Theme.font(14))
                    .lineLimit(2)
                Spacer()
                Button("Geri al") { store.undo() }
                    .font(Theme.font(14, .bold))
                    .foregroundStyle(.white)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(5))
                store.dismissUndo()
            }
        }
    }
}

/// Harita türü (standart, uydu, karma, arazi).
enum MapKind: String, CaseIterable, Identifiable {
    case standard, satellite, hybrid, terrain

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standart"
        case .satellite: "Uydu"
        case .hybrid: "Karma"
        case .terrain: "Arazi"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.europe.africa.fill"
        case .hybrid: "square.2.layers.3d"
        case .terrain: "mountain.2"
        }
    }
}

extension MKCoordinateRegion {
    /// Verilen noktaları kenarlarda pay bırakarak kapsayan bölge.
    init?(fitting coordinates: [CLLocationCoordinate2D], padding: Double = 1.4) {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * padding, 0.01),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * padding, 0.01))
        self.init(center: center, span: span)
    }

    /// Bir yere yakınlaşır; en yakın iki komşusu da görünsün diye pay
    /// bırakır (yer ortada, en az 800 m, en çok 5 km).
    init(focusing place: Place, among others: [Place]) {
        let distances = others.filter { $0.id != place.id }
            .map { $0.location.distance(from: place.location) }
            .sorted()
        let neighbor = distances.count >= 2 ? distances[1] : distances.first ?? 400
        let meters = min(max(neighbor * 2.4, 800), 5_000)
        self.init(center: place.coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
    }
}

/// Wikipedia yazısının tamamı, başlık başlık (dokununca açılır). "Dinle"
/// kartı özeti ve bu bölümleri art arda okur.
struct ArticleSections: View {
    let article: WikipediaService.Article
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(article.sections) { section in
                Button {
                    withAnimation(.snappy) {
                        if expanded.contains(section.id) { expanded.remove(section.id) } else { expanded.insert(section.id) }
                    }
                } label: {
                    HStack {
                        Text(section.heading).font(Theme.font(16, .semibold)).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: expanded.contains(section.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded.contains(section.id) {
                    Text(section.text)
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .padding(.bottom, 12)
                }
                Divider()
            }
        }
    }
}

extension WikipediaService.Summary {
    /// Dinlemek için özet ve yazının tamamı art arda.
    func adding(_ article: WikipediaService.Article?) -> WikipediaService.Summary {
        guard let article, !article.sections.isEmpty else { return self }
        var full = self
        full.extract = extract + "\n\n" + article.spokenText
        return full
    }
}

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
/// gün varsa hangi güne ekleneceği sorulur.
struct PlanDayButton: View {
    let place: Place
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let days = store.trip(for: place.city).days
        if let current = store.dayIndex(of: place) {
            Menu {
                Picker("Gün", selection: Binding(get: { current }, set: { store.move(place, toDay: $0) })) {
                    ForEach(0..<days, id: \.self) { Text("\($0 + 1). gün").tag($0) }
                }
                .pickerStyle(.inline)
                Button(role: .destructive) { store.removeFromPlan(place) } label: {
                    Label("Rotadan çıkar", systemImage: "minus.circle")
                }
            } label: {
                SecondaryLabel(title: "\(current + 1). gün", systemImage: "calendar", showsChevron: true)
            }
            .menuOrder(.fixed)
            .accessibilityHint(Text("Günü değiştir"))
        } else if days > 1 {
            Menu {
                ForEach(0..<days, id: \.self) { day in
                    Button("\(day + 1). güne ekle") { store.addToPlan([place.id], city: place.city, day: day) }
                }
            } label: {
                PrimaryLabel(title: "Rotaya ekle", systemImage: "plus")
            }
            .menuOrder(.fixed)
        } else {
            PrimaryButton(title: "Rotaya ekle", systemImage: "plus") {
                store.addToPlan([place.id], city: place.city)
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

/// Yerin fotoğrafı: Wikipedia'dan; yoksa tür ikonu.
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
        .task(id: place.wikipediaTitle) {
            guard let title = place.wikipediaTitle else { return }
            url = await WikipediaService.shared.thumbnailURL(englishTitle: title)
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

/// "Dinle" kartı: yerin Wikipedia yazısını iPhone sesiyle okur;
/// okurken dokununca duraklatır / sürdürür.
struct ListenCard: View {
    let title: String
    let summary: WikipediaService.Summary?
    @ObservedObject private var narrator = Narrator.shared

    var body: some View {
        let isPlaying = narrator.currentTitle == title
        HStack(spacing: 14) {
            Image(systemName: isPlaying && !narrator.isPaused ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.ink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Dinle").font(Theme.headline)
                Text(summary == nil ? LocalizedStringKey("Anlatım hazırlanıyor") : LocalizedStringKey("Türkçe anlatım · iPhone sesi"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            if isPlaying {
                narrator.togglePause()
            } else if let summary {
                narrator.speak(summary.extract, title: title, language: summary.language)
            }
        }
        .opacity(summary == nil ? 0.5 : 1)
        .accessibilityAddTraits(.isButton)
    }
}

/// Anlatım çalarken ekranın altında duran çubuk: ad, ilerleme, 10 sn geri,
/// oynat / duraklat, 10 sn ileri, kapat. Sayfa değişse de görünür kalır.
struct NarrationBar: View {
    @ObservedObject private var narrator = Narrator.shared

    var body: some View {
        ZStack {
            if let title = narrator.currentTitle { bar(title) }
        }
        .animation(.snappy, value: narrator.currentTitle)
    }

    private func bar(_ title: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                Text(title)
                    .font(Theme.font(15, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                control("gobackward.10", label: "10 saniye geri") { narrator.skip(by: -10) }
                Button { narrator.togglePause() } label: {
                    Image(systemName: narrator.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Theme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(narrator.isPaused ? LocalizedStringKey("Oynat") : LocalizedStringKey("Duraklat")))
                control("goforward.10", label: "10 saniye ileri") { narrator.skip(by: 10) }
                control("xmark", label: "Anlatımı kapat", size: 13) { narrator.stop() }
            }
            ProgressView(value: narrator.progress)
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .softShadow()
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func control(_ symbol: String, label: LocalizedStringKey, size: CGFloat = 19,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
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

/// Harita türü (standart, uydu, karma).
enum MapKind: String, CaseIterable, Identifiable {
    case standard, satellite, hybrid

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standart"
        case .satellite: "Uydu"
        case .hybrid: "Karma"
        }
    }

    /// Rota haritası: yalnızca bizim pinlerimiz görünür.
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
    }

    /// Keşfet haritası: zemin soluk, bizim renkli pinler öne çıksın.
    /// Sokak düzeyine inince Google Maps gibi Apple'ın yerleri de (müze,
    /// kafe, istasyon) görünür ve dokunulabilir.
    func exploreStyle(showingApplePlaces: Bool) -> MapStyle {
        let places: PointOfInterestCategories = showingApplePlaces ? .all : .excludingAll
        return switch self {
        case .standard: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: places)
        case .satellite: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: places)
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

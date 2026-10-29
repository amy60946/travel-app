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
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.font(16, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(.plain)
    }
}

/// Beyaz, çerçeveli ikincil düğme.
struct SecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.font(14, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
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
            url = await WikipediaService.shared.summary(englishTitle: title)?.thumbnailURL
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
                Text(summary == nil ? LocalizedStringKey("Anlatım hazırlanıyor") : LocalizedStringKey("Rehber anlatımı · iPhone sesi"))
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
}

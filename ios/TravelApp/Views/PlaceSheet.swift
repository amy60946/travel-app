import SwiftUI

/// Haritada kayıtlı bir yere dokununca alttan açılan pencere (Google Maps
/// gibi): ad ve tür; tek gün düğmesi (rotadaysa günü değiştirir, değilse
/// seçilen güne ekler), Aç, Yol tarifi (uygulamanın içinde); yana kayan
/// fotoğraflar (dokununca tam ekran), Dinle düğmesi ve Wikipedia'dan bilgi.
/// Yarım ekran açılır, yukarı çekilince ekranın %70'ine çıkar; üstte harita
/// hep görünür ve kullanılabilir.
struct PlaceSheet: View {
    let placeID: UUID
    let onOpen: (Place) -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var summary: WikipediaService.Summary?
    /// Yazının tamamı (başlık başlık); özetten sonra gelir.
    @State private var article: WikipediaService.Article?
    @State private var isLoadingArticle = false
    @State private var photos: [URL] = []
    /// Fotoğraflar sayfadan değil, yakında çekilenlerden mi geldi?
    @State private var photosAreNearby = false
    @State private var isLoading = true
    @State private var isLoadingPhotos = true
    /// Tam ekran açılan fotoğrafın sırası.
    @State private var viewerIndex: Int?
    @State private var guidance: GuidanceDestination?
    /// Google'dan puan, saatler, telefon, yorumlar (ve Wikipedia'da yoksa fotoğraflar).
    @State private var google: GooglePlaces.Details?

    var body: some View {
        if let place = store.place(placeID) {
            content(place)
                .task(id: placeID) { await load(place) }
                .task(id: placeID) {
                    google = nil
                    google = await GooglePlaces.shared.details(for: place, store: store)
                }
        }
    }

    /// Wikipedia'da yerin kendi fotoğrafı yoksa (restoran, kafe...) Google'ın fotoğrafları.
    private var usesGooglePhotos: Bool {
        guard let google, !google.photos.isEmpty else { return false }
        return !isLoadingPhotos && (photos.isEmpty || photosAreNearby)
    }

    private func content(_ place: Place) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(place)
                if let google { GooglePlaceInfo(details: google, showsPhotos: false, showsDetails: false) }
                actions(place)
                if usesGooglePhotos, let google {
                    GooglePlaceInfo(details: google, showsRating: false, showsDetails: false)
                } else {
                    photoStrip(place)
                }
                about(place)
                if let google { GooglePlaceInfo(details: google, showsRating: false, showsPhotos: false) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .background(.white)
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        // Bu yer çalıyorsa oynatıcı "Dinle" kartının kendisi; alttaki çubuk gizlenir.
        .narrationBarInset(hiding: place.name)
        .fullScreenCover(isPresented: Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })) {
            PhotoViewer(photos: photos, index: viewerIndex ?? 0)
        }
        .fullScreenCover(item: $guidance) { GuidanceView(destination: $0) }
    }

    private func header(_ place: Place) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: place.category, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(Theme.font(22, .bold)).lineLimit(2)
                Text(verbatim: "\(place.category.title) · \(place.city)")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            CollectButton(item: .place(place), size: 30)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Kapat"))
        }
    }

    /// Gün düğmesi (rotadaysa "2. gün ⌄", değilse "Rotaya ekle"), Aç, Yol tarifi.
    private func actions(_ place: Place) -> some View {
        HStack(spacing: 8) {
            PlanDayButton(place: place)
            SecondaryButton(title: "Aç", systemImage: "arrow.up.right") { onOpen(place) }
            DirectionsButton { guidance = GuidanceDestination(place: place) }
        }
    }

    /// Yana kayan fotoğraflar; yüklenirken gri kutular.
    @ViewBuilder
    private func photoStrip(_ place: Place) -> some View {
        if isLoadingPhotos && photos.isEmpty {
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface)
                        .frame(width: 240, height: 170)
                }
            }
        } else if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, url in
                            Button { viewerIndex = index } label: {
                                Theme.surface
                                    .overlay {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Theme.surface
                                        }
                                    }
                                    .frame(width: 240, height: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Fotoğrafı büyüt"))
                        }
                    }
                }
                .padding(.horizontal, -20)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                Text(photosAreNearby
                     ? LocalizedStringKey("Fotoğraflar: yakında çekilenler, Wikimedia Commons")
                     : LocalizedStringKey("Fotoğraflar: Wikipedia / Wikimedia Commons"))
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// Dinle kartı ve Wikipedia yazısı; yazı yoksa notu.
    @ViewBuilder
    private func about(_ place: Place) -> some View {
        if let summary {
            ListenCard(title: place.name, summary: summary.adding(article))
            VStack(alignment: .leading, spacing: 8) {
                Text("Hakkında").font(Theme.headline)
                Text(summary.extract).font(Theme.body)
                if let article {
                    ArticleSections(article: article).padding(.top, 4)
                } else if isLoadingArticle {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Yazının devamı hazırlanıyor").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                }
                WikipediaCredit(summary: summary)
            }
        } else if isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            Text("Bu yer hakkında Wikipedia'da yazı bulunamadı.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.muted)
        }
        if !place.note.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notun").font(Theme.headline)
                Text(place.note).font(Theme.body)
            }
        }
    }

    /// Wikipedia sayfası yoksa yakındaki sayfalardan adı örtüşeni bulup
    /// yere kaydeder; fotoğraf sayfada yoksa yakında çekilenler gösterilir.
    private func load(_ place: Place) async {
        isLoading = true
        isLoadingPhotos = true
        summary = nil
        article = nil
        photos = []
        photosAreNearby = false
        defer { isLoading = false }

        var title = place.wikipediaTitle
        if title == nil, let found = await WikipediaService.shared.findArticle(
            name: place.name, city: place.city, latitude: place.latitude, longitude: place.longitude) {
            title = found
            if var updated = store.place(place.id) {
                updated.wikipediaTitle = found
                store.update(updated)
            }
        }
        // Fotoğraflar yazıyı (çeviri sürebilir) beklemeden gelsin.
        let englishTitle = title
        async let foundSummary = loadSummary(englishTitle)
        if let englishTitle { photos = await WikipediaService.shared.photos(englishTitle: englishTitle) }
        if photos.isEmpty {
            photos = await WikipediaService.shared.nearbyPhotos(latitude: place.latitude, longitude: place.longitude)
            photosAreNearby = !photos.isEmpty
        }
        isLoadingPhotos = false
        summary = await foundSummary
        // Yazının tamamı (çevirisi sürebilir) özetten sonra.
        if let englishTitle, summary != nil {
            isLoadingArticle = true
            article = await WikipediaService.shared.article(englishTitle: englishTitle)
            isLoadingArticle = false
        }
        #if DEBUG
        // Ekran görüntüsü için: `-screen photo` fotoğrafı tam ekran açar.
        if UserDefaults.standard.string(forKey: "screen") == "photo", !photos.isEmpty { viewerIndex = 0 }
        #endif
    }

    private func loadSummary(_ englishTitle: String?) async -> WikipediaService.Summary? {
        guard let englishTitle else { return nil }
        return await WikipediaService.shared.summary(englishTitle: englishTitle)
    }
}

extension PresentationDetent {
    /// Yer penceresi: yarım ekran; yukarı çekilince ekranın %70'i (üstte harita kalır).
    static let placeHalf = PresentationDetent.fraction(0.5)
    static let placeTall = PresentationDetent.fraction(0.7)
}

extension View {
    /// Yer penceresinin Google Maps gibi davranışı: yarım ekran açılır,
    /// yukarı çekilince (ya da içi yukarı kaydırılınca) ekranın %70'ine
    /// çıkar; üstteki harita görünür ve kullanılır.
    func placeSheetPresentation(detent: Binding<PresentationDetent>) -> some View {
        presentationDetents([.placeHalf, .placeTall], selection: detent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .placeTall))
            .presentationContentInteraction(.resizes)
            .presentationCornerRadius(Theme.sheetRadius)
    }
}

import CoreLocation
import SwiftUI

/// Haritada Google'ın bir yerine (restoran, müze, kafe...) dokununca alttan
/// açılan pencere (Google Maps gibi): ad, tür, puan; Kaydet ve Yol tarifi;
/// altında Google'ın fotoğrafları, saatleri, telefonu, web sitesi ve
/// yorumları. Kaydedince kayıtlı yerin penceresine geçer.
struct GooglePlaceSheet: View {
    let place: GooglePlaceRef
    let onSaved: (Place) -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = PlaceImporter()

    @State private var details: GooglePlaces.Details?
    @State private var isLoading = true
    @State private var saving = false
    @State private var guidance: GuidanceDestination?

    private var category: PlaceCategory {
        details?.category ?? PlaceCategory.guess(name: place.name) ?? .sight
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                if let details {
                    GooglePlaceInfo(details: details)
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                } else {
                    Text(GoogleAPI.isConfigured
                         ? LocalizedStringKey("Google'dan bilgi şu an alınamadı.")
                         : LocalizedStringKey("Google Haritalar anahtarı henüz girilmedi"))
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .background(.white)
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .task(id: place.id) {
            isLoading = true
            details = await GooglePlaces.shared.details(id: place.id)
            isLoading = false
        }
        .fullScreenCover(item: $guidance) { GuidanceView(destination: $0) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: category, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(details?.name ?? place.name).font(Theme.font(22, .bold)).lineLimit(2)
                Text(details?.typeName ?? category.title)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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

    private var actions: some View {
        HStack(spacing: 8) {
            PrimaryButton(title: saving ? LocalizedStringKey("Kaydediliyor…") : LocalizedStringKey("Kaydet"),
                          systemImage: "bookmark") {
                Task { await save() }
            }
            .disabled(saving)
            DirectionsButton {
                guidance = GuidanceDestination(name: details?.name ?? place.name,
                                               coordinate: details?.coordinate ?? place.coordinate,
                                               category: category)
            }
        }
    }

    /// Yeri kaydeder (rotaya eklemez); şehir konumdan bulunur.
    private func save() async {
        let name = details?.name ?? place.name
        let coordinate = details?.coordinate ?? place.coordinate
        if let saved = store.savedPlace(googleID: place.id, named: name, near: coordinate) {
            onSaved(saved)
            return
        }
        saving = true
        defer { saving = false }
        let city = await importer.city(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                       knownCities: store.cities)
        let saved = Place(name: name, city: city, latitude: coordinate.latitude, longitude: coordinate.longitude,
                          category: category, source: .search, googlePlaceID: place.id)
        store.add(saved, plan: false)
        onSaved(saved)
    }
}

/// Haritada dokunulan Google yeri.
struct GooglePlaceRef: Identifiable, Equatable {
    /// Google'ın yer kimliği.
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Google'dan gelen bilgiler: puan, açık/kapalı, fotoğraflar, adres,
/// saatler, telefon, web sitesi ve yorumlar. Google'ın kuralı gereği
/// fotoğrafın ve yorumun sahibinin adı ve "Google Maps" yazısı görünür.
struct GooglePlaceInfo: View {
    let details: GooglePlaces.Details
    /// Kayıtlı yerin penceresinde parçalar ayrı yerlerde gösterilir: puan
    /// adın altında, fotoğraflar (Wikipedia'da yoksa) ortada, gerisi altta.
    var showsRating = true
    var showsPhotos = true
    var showsDetails = true
    @State private var photoURLs: [String: URL] = [:]
    @State private var viewerIndex: Int?
    @State private var showsHours = false

    /// Yüklenmiş fotoğraflar, sırasıyla (tam ekran görüntüleyici için).
    private var loadedPhotos: [URL] { details.photos.compactMap { photoURLs[$0.id] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsRating { ratingRow }
            if showsPhotos && !details.photos.isEmpty { photoStrip }
            if showsDetails {
                if let summary = details.summary, !summary.isEmpty {
                    Text(summary).font(Theme.body)
                }
                infoRows
                if !details.reviews.isEmpty { reviews }
                Text("Bilgiler: Google Maps")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })) {
            PhotoViewer(photos: loadedPhotos, index: viewerIndex ?? 0)
        }
    }

    // MARK: - Puan

    @ViewBuilder
    private var ratingRow: some View {
        let parts = [priceText, openText].compactMap { $0 }
        if details.rating != nil || !parts.isEmpty {
            HStack(spacing: 6) {
                if let rating = details.rating {
                    Text(rating.formatted(.number.precision(.fractionLength(1))))
                        .font(Theme.font(15, .semibold))
                    Stars(rating: rating, size: 13)
                    if let count = details.ratingCount {
                        Text(verbatim: "(\(count.formatted()))")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.muted)
                    }
                }
                ForEach(parts, id: \.self) { part in
                    Text(verbatim: "·").foregroundStyle(Theme.muted)
                    Text(part)
                        .font(Theme.font(14, part == openText ? .semibold : .regular))
                        .foregroundStyle(part == openText ? (details.openNow == true ? Color.green : Color.red) : Theme.muted)
                }
            }
            .lineLimit(1)
        }
    }

    private var priceText: String? {
        switch details.priceLevel {
        case 0: String(localized: "Ücretsiz")
        case 1: String(localized: "Ucuz")
        case 2: String(localized: "Orta fiyat")
        case 3: String(localized: "Pahalı")
        case 4: String(localized: "Çok pahalı")
        default: nil
        }
    }

    private var openText: String? {
        details.openNow.map { $0 ? String(localized: "Şu an açık") : String(localized: "Şu an kapalı") }
    }

    // MARK: - Fotoğraflar

    /// Yana kayan fotoğraflar; her fotoğraf görününce istenir (fotoğraf
    /// isteği ücretsiz kotadan düşer, görülmeyen istenmez).
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(details.photos) { photo in
                    photoCell(photo)
                }
            }
        }
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func photoCell(_ photo: GooglePlaces.Photo) -> some View {
        Button {
            if let url = photoURLs[photo.id] { viewerIndex = loadedPhotos.firstIndex(of: url) }
        } label: {
            Theme.surface
                .overlay {
                    if let url = photoURLs[photo.id] {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Theme.surface
                        }
                    }
                }
                .frame(width: 240, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(alignment: .bottomLeading) {
                    if let author = photo.author {
                        Text(author)
                            .font(Theme.font(11, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .padding(8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Fotoğrafı büyüt"))
        .task(id: photo.id) {
            guard photoURLs[photo.id] == nil else { return }
            photoURLs[photo.id] = await GooglePlaces.shared.photoURL(photo)
        }
    }

    // MARK: - Adres, saatler, telefon, web sitesi

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let address = details.address {
                InfoRow(systemImage: "mappin.and.ellipse") { Text(address) }
            }
            if !details.hours.isEmpty {
                Button { withAnimation(.snappy) { showsHours.toggle() } } label: {
                    InfoRow(systemImage: "clock") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(openText ?? String(localized: "Açılış saatleri"))
                                    .foregroundStyle(details.openNow == true ? Color.green
                                                     : details.openNow == false ? Color.red : Theme.ink)
                                Image(systemName: showsHours ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                            if showsHours {
                                ForEach(details.hours, id: \.self) { line in
                                    Text(line).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let phone = details.phone {
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:\(digits)") {
                    Link(destination: url) { InfoRow(systemImage: "phone") { Text(phone) } }
                } else {
                    InfoRow(systemImage: "phone") { Text(phone) }
                }
            }
            if let website = details.website {
                Link(destination: website) {
                    InfoRow(systemImage: "globe") { Text(website.host() ?? website.absoluteString).lineLimit(1) }
                }
            }
            if let maps = details.mapsURL {
                Link(destination: maps) {
                    InfoRow(systemImage: "map") { Text("Google Maps'te aç") }
                }
            }
        }
        .tint(Theme.ink)
    }

    // MARK: - Yorumlar

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Yorumlar").font(Theme.headline)
            ForEach(details.reviews) { review in
                ReviewRow(review: review)
                if review.id != details.reviews.last?.id { Divider() }
            }
        }
    }
}

/// Bilgi satırı: solda simge, yanında yazı; altında ince çizgi.
private struct InfoRow<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(width: 20)
            content
                .font(Theme.font(15))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 34) }
        .contentShape(Rectangle())
    }
}

/// Google yorumu: yazanın fotoğrafı ve adı, yıldızlar, ne zaman, yazı.
private struct ReviewRow: View {
    let review: GooglePlaces.Review
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AsyncImage(url: review.authorPhoto) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Theme.surface)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    if let url = review.authorURL {
                        Link(review.author, destination: url)
                            .font(Theme.font(14, .semibold))
                            .tint(Theme.ink)
                    } else {
                        Text(review.author).font(Theme.font(14, .semibold))
                    }
                    HStack(spacing: 6) {
                        Stars(rating: Double(review.rating), size: 11)
                        Text(review.when).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                }
            }
            Text(review.text)
                .font(Theme.font(14))
                .lineLimit(expanded ? nil : 5)
                .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        }
    }
}

/// Beş yıldız: puan kadarı dolu (yarım yıldız da).
struct Stars: View {
    let rating: Double
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(index))
                    .font(.system(size: size))
                    .foregroundStyle(Color(hex: 0xFBBC04))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(rating.formatted(.number.precision(.fractionLength(1)))) / 5"))
    }

    private func symbol(_ index: Int) -> String {
        let value = rating - Double(index)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

extension GooglePlaces {
    /// Kayıtlı bir yerin Google bilgileri. Google kimliği yoksa adıyla ve
    /// konumuyla bulunur (ücretsiz) ve yere kaydedilir; bulunan yer 500
    /// metreden uzaksa başka bir yerdir, kullanılmaz.
    func details(for place: Place, store: AppStore) async -> Details? {
        guard GoogleAPI.isConfigured else { return nil }
        let knownID = place.googlePlaceID
        var foundID = knownID
        if foundID == nil { foundID = await findID(name: place.name, near: place.coordinate) }
        guard let id = foundID, let found = await details(id: id) else { return nil }
        let distance = CLLocation(latitude: found.latitude, longitude: found.longitude).distance(from: place.location)
        guard knownID != nil || distance < 500 else { return nil }
        if knownID == nil, var updated = store.place(place.id) {
            updated.googlePlaceID = id
            store.update(updated)
        }
        return found
    }
}

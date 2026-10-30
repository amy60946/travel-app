import MapKit
import SwiftUI

/// Yer sayfası: fotoğraf, ad, tür; Dinle kartı; açıklama ve kaynağı;
/// alt çubukta gün düğmesi ("Rotaya ekle" ya da "2. gün ⌄").
struct PlaceDetailView: View {
    let placeID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var summary: WikipediaService.Summary?
    @State private var article: WikipediaService.Article?
    @State private var isLoading = true
    @State private var google: GooglePlaces.Details?
    @State private var editsNote = false

    var body: some View {
        if let place = store.place(placeID) {
            content(place)
        } else {
            Text("Bu yer artık kayıtlı değil.")
                .onAppear { dismiss() }
        }
    }

    private func content(_ place: Place) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlaceThumbnail(place: place, cornerRadius: 0)
                    .frame(height: 280)
                    .overlay(alignment: .topLeading) {
                        CircleIconButton(systemImage: "chevron.left") { dismiss() }
                            .padding(.leading, 16)
                            .padding(.top, 56)
                    }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name).font(Theme.title)
                        HStack(spacing: 6) {
                            categoryMenu(place)
                            Text(verbatim: "· \(place.city)").foregroundStyle(Theme.muted)
                        }
                        .font(Theme.body)
                        HStack {
                            if let note = place.source.savedNote {
                                Label(note, systemImage: "bookmark.fill")
                                    .font(Theme.caption)
                            }
                            if place.isEstimated { EstimatedTag() }
                        }
                        if let url = place.sourceURL {
                            Link(destination: url) {
                                Label("Kaydettiğin gönderiyi aç", systemImage: "arrow.up.right.square")
                                    .font(Theme.caption)
                                    .underline()
                            }
                            .foregroundStyle(Theme.muted)
                        }
                        Text("Ortalama süre: \(place.category.averageMinutes) dk")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.muted)
                    }

                    ListenCard(title: place.name, summary: summary?.adding(article))

                    if let summary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hakkında").font(Theme.headline)
                            Text(summary.extract).font(Theme.body)
                            if let article { ArticleSections(article: article).padding(.top, 4) }
                            WikipediaCredit(summary: summary)
                        }
                    } else if isLoading {
                        ProgressView()
                    }

                    PlaceNoteCard(note: place.note) { editsNote = true }

                    if let google { GooglePlaceInfo(details: google) }

                    StaticGoogleMap(center: place.coordinate, zoom: 15.5, markers: [
                        GoogleMap.Marker(id: "place", coordinate: place.coordinate, key: place.name, anchorsBottom: true) {
                            PlacePin(place: place, isActive: true).padding(6)
                        },
                    ])
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { bottomBar(place) }
        .sheet(isPresented: $editsNote) { PlaceEditor(place: place, focusesNote: true) }
        .task(id: place.wikipediaTitle) {
            isLoading = true
            if let title = place.wikipediaTitle {
                summary = await WikipediaService.shared.summary(englishTitle: title)
            }
            isLoading = false
            if let title = place.wikipediaTitle, summary != nil {
                article = await WikipediaService.shared.article(englishTitle: title)
            }
        }
        .task(id: place.id) { google = await GooglePlaces.shared.details(for: place, store: store) }
    }

    /// Tür (haritadaki pinin rengi ve simgesi); yanlış tahmin edildiyse
    /// buradan değiştirilir.
    private func categoryMenu(_ place: Place) -> some View {
        Menu {
            Picker("Tür", selection: Binding(get: { place.category }, set: { category in
                var updated = place
                updated.category = category
                store.update(updated)
            })) {
                ForEach(PlaceCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                CategoryIcon(category: place.category, size: 22)
                Text(place.category.title)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
        }
        .accessibilityHint(Text("Türü değiştir"))
    }

    private func bottomBar(_ place: Place) -> some View {
        HStack {
            Text(place.city).font(Theme.headline)
            Spacer()
            PlanDayButton(place: place)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) { Divider() }
    }
}

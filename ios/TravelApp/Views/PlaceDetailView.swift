import MapKit
import SwiftUI

/// Yer sayfası: fotoğraf, ad, tür; Dinle kartı; açıklama ve kaynağı;
/// alt çubukta "Rotaya ekle" ya da "Rotada · Çıkar".
struct PlaceDetailView: View {
    let placeID: UUID
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var narrator = Narrator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var summary: WikipediaService.Summary?
    @State private var isLoading = true

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
                        Text("\(place.category.title) · \(place.city)")
                            .font(Theme.body)
                            .foregroundStyle(Theme.muted)
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

                    listenCard(place)

                    if let summary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hakkında").font(Theme.headline)
                            Text(summary.extract).font(Theme.body)
                            if let url = summary.pageURL {
                                Link(destination: url) {
                                    Text("Kaynak: Wikipedia (CC BY-SA)")
                                        .font(Theme.caption)
                                        .underline()
                                }
                                .foregroundStyle(Theme.muted)
                            }
                        }
                    } else if isLoading {
                        ProgressView()
                    }

                    if !place.note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notun").font(Theme.headline)
                            Text(place.note).font(Theme.body)
                        }
                    }

                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: place.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                        Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                            PlacePin(place: place, isActive: true)
                        }
                        .annotationTitles(.hidden)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { bottomBar(place) }
        .task(id: place.wikipediaTitle) {
            isLoading = true
            if let title = place.wikipediaTitle {
                summary = await WikipediaService.shared.summary(englishTitle: title)
            }
            isLoading = false
        }
    }

    private func listenCard(_ place: Place) -> some View {
        let isPlaying = narrator.currentTitle == place.name
        return HStack(spacing: 14) {
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
                narrator.speak(summary.extract, title: place.name, language: summary.language)
            }
        }
        .opacity(summary == nil ? 0.5 : 1)
    }

    private func bottomBar(_ place: Place) -> some View {
        HStack {
            if store.isPlanned(place) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rotada").font(Theme.headline)
                    if let day = store.dayIndex(of: place) {
                        Text("\(day + 1). gün").font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                SecondaryButton(title: "Çıkar", systemImage: "minus") { store.removeFromPlan(place) }
            } else {
                Text(place.city).font(Theme.headline)
                Spacer()
                PrimaryButton(title: "Rotaya ekle", systemImage: "plus") {
                    store.addToPlan([place.id], city: place.city)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) { Divider() }
    }
}

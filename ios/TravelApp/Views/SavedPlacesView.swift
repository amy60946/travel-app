import SwiftUI

/// Kayıtlarım: aktarılan yerler 2 sütun; kaynağa göre süzme; seçip
/// "Rotaya ekle".
struct SavedPlacesView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var path: [Route]
    @State private var filter: PlaceSource?
    @State private var selection: Set<UUID> = []
    @State private var showImport = false

    private let filters: [PlaceSource] = [.instagram, .tiktok, .googleMaps]

    private var visible: [Place] {
        store.places
            .filter { filter == nil || $0.source == filter }
            .sorted { $0.addedAt > $1.addedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kayıtlarım").font(Theme.title)
                Spacer()
                SecondaryButton(title: "Veri aktar", systemImage: "square.and.arrow.down") { showImport = true }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: String(localized: "Tümü"), isSelected: filter == nil) { filter = nil }
                    ForEach(filters) { source in
                        Chip(title: source.title, isSelected: filter == source) { filter = source }
                    }
                }
                .padding(.horizontal, 20)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(visible) { place in
                        SavedCard(place: place,
                                  isPlanned: store.isPlanned(place),
                                  isSelected: selection.contains(place.id),
                                  onOpen: { path.append(.place(place.id)) },
                                  onToggle: { toggle(place) })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 140)
            }
        }
        .sheet(isPresented: $showImport) { ImportView() }
        .overlay(alignment: .bottom) {
            if !selection.isEmpty {
                PrimaryButton(title: "Rotaya ekle (\(selection.count))", systemImage: "plus") {
                    addSelection()
                }
                .padding(.bottom, 84)
            }
        }
    }

    private func toggle(_ place: Place) {
        if selection.contains(place.id) { selection.remove(place.id) } else { selection.insert(place.id) }
    }

    /// Gün kendiliğinden seçilir: planlayıcı yeri en yakın güne koyar.
    private func addSelection() {
        let chosen = store.places.filter { selection.contains($0.id) }
        for (city, list) in Dictionary(grouping: chosen, by: \.city) {
            store.addToPlan(list.map(\.id), city: city)
        }
        selection.removeAll()
    }
}

private struct SavedCard: View {
    let place: Place
    let isPlanned: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                PlaceThumbnail(place: place)
                    .frame(height: 150)
                    .onTapGesture(perform: onOpen)
                SourceTag(source: place.source).padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if !isPlanned {
                    Button(action: onToggle) {
                        Image(systemName: isSelected ? "checkmark" : "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isSelected ? .white : Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(isSelected ? Theme.ink : .white, in: Circle())
                            .softShadow()
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
            Text(place.name).font(Theme.font(15, .semibold)).lineLimit(1)
            HStack(spacing: 4) {
                Text(place.category.title)
                Text("·")
                Text(place.city)
                if isPlanned { Text("·"); Text("Rotada") }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            if place.isEstimated { EstimatedTag() }
        }
    }
}

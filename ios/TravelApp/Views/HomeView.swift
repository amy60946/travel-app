import MapKit
import SwiftUI

/// Ana sayfa (Gezim): kürede şehir pinleri; altta Gezilerim / Kayıtlarım
/// listesi.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var path: [Route]
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: .init(latitude: 35.68, longitude: 139.76), distance: 30_000_000))
    @State private var section = 0
    @State private var showSearch = false

    private var listedCities: [AppStore.CitySummary] {
        section == 0 ? store.cities.filter(\.hasTrip) : store.cities
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                ForEach(store.cities) { city in
                    Annotation(city.name, coordinate: city.coordinate, anchor: .bottom) {
                        Button { path.append(.city(city.name)) } label: {
                            CityPin(city: city)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            // Küre alttaki panelin üstünde, görünen alanın ortasında dursun.
            .safeAreaPadding(.bottom, 300)
            .ignoresSafeArea()

            HStack {
                Text("Gezim").font(Theme.title)
                Spacer()
                CircleIconButton(systemImage: "magnifyingglass") { showSearch = true }
                    .accessibilityLabel(Text("Yer ara"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            VStack { Spacer(); bottomPanel }
        }
        .task(id: store.cities.map(\.name)) { centerOnCities() }
        .sheet(isPresented: $showSearch) {
            AddPlaceView(city: store.cities.first?.name ?? "Tokyo")
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $section) {
                Text("Gezilerim").tag(0)
                Text("Kayıtlarım").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            if listedCities.isEmpty {
                Text(section == 0
                     ? LocalizedStringKey("Henüz gezi yok. Kayıtlarım'dan bir şehir seç, rota oluştur.")
                     : LocalizedStringKey("Henüz kayıt yok. + ile yer ekle ya da veri aktar."))
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(listedCities) { city in
                        Button { path.append(.city(city.name)) } label: {
                            CityRow(city: city, days: store.trip(for: city.name).days)
                        }
                        .buttonStyle(.plain)
                        if city.id != listedCities.last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .padding(.bottom, 80)
        .background {
            // Panel ekranın alt kenarına kadar uzansın; altta harita görünmesin.
            UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius, topTrailingRadius: Theme.sheetRadius)
                .fill(.white)
                .ignoresSafeArea(edges: .bottom)
        }
        .softShadow()
    }

    /// Küreyi kayıtlı şehirlerin ortasına çevirir.
    private func centerOnCities() {
        let cities = store.cities
        guard !cities.isEmpty else { return }
        let latitude = cities.map(\.latitude).reduce(0, +) / Double(cities.count)
        let longitude = cities.map(\.longitude).reduce(0, +) / Double(cities.count)
        position = .camera(MapCamera(centerCoordinate: .init(latitude: latitude, longitude: longitude),
                                     distance: 30_000_000))
    }
}

/// Alttaki listede bir şehir: fotoğraf, ad, gün ve yer sayısı.
private struct CityRow: View {
    let city: AppStore.CitySummary
    let days: Int

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover = city.coverPlace {
                    PlaceThumbnail(place: cover, cornerRadius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                        .overlay(Image(systemName: "mappin").foregroundStyle(Theme.muted))
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(city.name).font(Theme.font(17, .semibold))
                Text(city.hasTrip
                     ? LocalizedStringKey("\(days) gün · \(city.placeCount) yer")
                     : LocalizedStringKey("\(city.placeCount) kayıtlı yer · rota yok"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if city.hasTrip {
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            } else {
                Text("Rota oluştur").font(Theme.font(14, .semibold)).underline()
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Kürede şehir pini: fotoğraf + ad + yer sayısı; sıradaki gezi siyah.
private struct CityPin: View {
    let city: AppStore.CitySummary

    var body: some View {
        HStack(spacing: 6) {
            if let cover = city.coverPlace {
                PlaceThumbnail(place: cover, cornerRadius: 12)
                    .frame(width: 24, height: 24)
            }
            Text("\(city.name) · \(city.placeCount)")
                .font(Theme.font(13, .semibold))
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .foregroundStyle(city.hasTrip ? .white : Theme.ink)
        .background(city.hasTrip ? Theme.ink : .white, in: Capsule())
        .softShadow()
    }
}

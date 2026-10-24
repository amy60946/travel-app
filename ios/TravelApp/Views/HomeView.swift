import MapKit
import SwiftUI

/// Ana sayfa: kürede şehir pinleri; altta Gezilerim / Kayıtlarım.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var path: [Route]
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: .init(latitude: 35.68, longitude: 139.76), distance: 18_000_000))
    @State private var section = 0

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
            .ignoresSafeArea()

            Text("Keşfet")
                .font(Theme.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack { Spacer(); bottomPanel }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $section) {
                Text("Gezilerim").tag(0)
                Text("Kayıtlarım").tag(1)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section == 0 ? store.cities.filter(\.hasTrip) : store.cities) { city in
                        Button { path.append(.city(city.name)) } label: {
                            CityCard(city: city)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .padding(.bottom, 80)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius, topTrailingRadius: Theme.sheetRadius))
        .softShadow()
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

private struct CityCard: View {
    let city: AppStore.CitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let cover = city.coverPlace {
                    PlaceThumbnail(place: cover)
                } else {
                    RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface)
                }
            }
            .frame(width: 150, height: 110)
            Text(city.name).font(Theme.headline)
            Text("\(city.placeCount) yer").font(Theme.caption).foregroundStyle(Theme.muted)
        }
    }
}

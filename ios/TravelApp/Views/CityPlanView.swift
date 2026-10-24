import MapKit
import SwiftUI

/// Şehir planı: harita üstte (gün numaralı pinler, sokaklardan rota),
/// günler altta; gün sayısı − / +, tempo, "Planla / Yürü", "+" menüsü.
struct CityPlanView: View {
    let city: String
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedDay = 0
    @State private var route: WalkingRoutes.DayRoute?
    @State private var mapKind: MapKind = .standard
    @State private var sheet: AddSheet?

    private var plan: (days: [[Place]], leftOver: [Place]) { store.dayPlan(for: city) }
    private var trip: Trip { store.trip(for: city) }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 360)
                .overlay(alignment: .top) { header }
                .overlay(alignment: .bottomTrailing) { mapKindMenu }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { index, stops in
                        DayCard(index: index, stops: stops, isSelected: index == selectedDay,
                                route: index == selectedDay ? route : nil,
                                onSelect: { selectedDay = index },
                                onOpen: { path.append(.place($0.id)) },
                                onLighten: { store.lightenDay(index, city: city) },
                                onWalk: { path.append(.walk(city: city, day: index)) })
                    }
                    if !plan.leftOver.isEmpty {
                        Text("\(plan.leftOver.count) yer sığmadı. Gün ekle ya da tempoyu artır.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Text("Harita ve yol tarifi: Apple Haritalar")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
                .padding(.bottom, 80)
            }
        }
        .overlay(alignment: .bottomTrailing) { addMenu }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 90) }
        .animation(.snappy, value: store.undoMessage)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { $0.view }
        .task(id: routeKey) { await loadRoute() }
    }

    // MARK: - Harita

    private var map: some View {
        Map(position: $position) {
            ForEach(Array(plan.days.enumerated()), id: \.offset) { dayIndex, stops in
                ForEach(stops) { place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        Button { selectedDay = dayIndex } label: {
                            DayBadge(number: dayIndex + 1, size: dayIndex == selectedDay ? 30 : 22)
                                .opacity(dayIndex == selectedDay ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(dayIndex == selectedDay ? .visible : .hidden)
                }
            }
            if let route {
                ForEach(Array(route.polylines.enumerated()), id: \.offset) { _, line in
                    MapPolyline(line).stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .mapStyle(mapKind.style)
        .onAppear(perform: focusSelectedDay)
        .onChange(of: selectedDay) { focusSelectedDay() }
    }

    private var header: some View {
        HStack {
            CircleIconButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            Text(city)
                .font(Theme.font(17, .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: Capsule())
                .softShadow()
            Spacer()
            Button {
                path.append(.walk(city: city, day: selectedDay))
            } label: {
                Label("Yürü", systemImage: "figure.walk")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
            }
            .disabled(plan.days.indices.contains(selectedDay) ? plan.days[selectedDay].isEmpty : true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var mapKindMenu: some View {
        Menu {
            Picker("Harita türü", selection: $mapKind) {
                ForEach(MapKind.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: "map")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(.white, in: Circle())
                .softShadow()
        }
        .padding(12)
    }

    // MARK: - Kontroller

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 14) {
                    stepButton("minus") { store.setDays(trip.days - 1, city: city) }
                    Text("\(trip.days) gün").font(Theme.headline).frame(minWidth: 56)
                    stepButton("plus") { store.setDays(trip.days + 1, city: city) }
                }
                Spacer()
                Menu {
                    Picker("Tempo", selection: Binding(get: { trip.pace }, set: { store.setPace($0, city: city) })) {
                        ForEach(Pace.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(trip.pace.title)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(Capsule().stroke(Theme.hairline))
                }
            }
            Text("\(trip.pace.maxStops(days: trip.days)) yer sığar · rotada \(trip.placeIDs.count) yer")
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    private var addMenu: some View {
        Menu {
            Button { sheet = .addPlace(city: city) } label: { Label("Yer ekle", systemImage: "magnifyingglass") }
            Button { sheet = .addPlace(city: city) } label: {
                Label("Kayıtlarından ekle", systemImage: "bookmark")
            }
            Button { sheet = .customPlace(city: city) } label: { Label("Kendi yerini oluştur", systemImage: "mappin.and.ellipse") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.ink, in: Circle())
                .softShadow()
        }
        .padding(20)
    }

    // MARK: - Rota

    private var routeKey: String {
        guard plan.days.indices.contains(selectedDay) else { return "" }
        return plan.days[selectedDay].map(\.id.uuidString).joined(separator: ",")
    }

    private func loadRoute() async {
        guard plan.days.indices.contains(selectedDay) else { route = nil; return }
        route = await WalkingRoutes.route(through: plan.days[selectedDay])
    }

    private func focusSelectedDay() {
        let days = plan.days
        let stops = days.indices.contains(selectedDay) && !days[selectedDay].isEmpty
            ? days[selectedDay] : days.flatMap { $0 }
        if let region = MKCoordinateRegion(fitting: stops.map(\.coordinate)) {
            withAnimation { position = .region(region) }
        }
    }
}

private struct DayCard: View {
    let index: Int
    let stops: [Place]
    let isSelected: Bool
    let route: WalkingRoutes.DayRoute?
    let onSelect: () -> Void
    let onOpen: (Place) -> Void
    let onLighten: () -> Void
    let onWalk: () -> Void

    private var visitMinutes: Int { stops.map(\.category.averageMinutes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DayBadge(number: index + 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(index + 1). gün").font(Theme.headline)
                    if let route {
                        Text("\(stops.count) durak · \(Int((route.meters / 1000).rounded())) km yürüyüş · ~\((visitMinutes + route.minutes) / 60) sa")
                            .font(Theme.caption).foregroundStyle(Theme.muted)
                    } else {
                        Text("\(stops.count) durak").font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            if stops.isEmpty {
                Text("Bu gün boş. \"+\" ile yer ekleyebilirsin.")
                    .font(Theme.caption).foregroundStyle(Theme.muted)
            }
            ForEach(stops) { place in
                Button { onOpen(place) } label: {
                    HStack(spacing: 12) {
                        PlaceThumbnail(place: place, cornerRadius: 10).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(Theme.font(15, .semibold))
                            Text(place.category.title).font(Theme.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if place.isEstimated { EstimatedTag() }
                        Image(systemName: "chevron.right").foregroundStyle(Theme.hairline)
                    }
                }
                .buttonStyle(.plain)
            }

            if isSelected && !stops.isEmpty {
                HStack {
                    SecondaryButton(title: "Günü hafiflet", systemImage: "minus.circle", action: onLighten)
                    Spacer()
                    PrimaryButton(title: "Yürüyüşe başla", systemImage: "figure.walk", action: onWalk)
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .stroke(isSelected ? Theme.ink : Theme.hairlineLight, lineWidth: isSelected ? 1.5 : 1))
    }
}

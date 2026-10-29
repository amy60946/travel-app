import MapKit
import SwiftUI

/// Şehir planı: harita üstte (türün renkli pinleri, köşede gün numarası,
/// sokaklardan rota), günler altta sade bir liste. Bir yere dokununca
/// harita o yere ve yanındaki yerlere yakınlaşır, alttan yer penceresi
/// açılır; harita görünür kalır. Yer, penceredeki gün düğmeleriyle ya da
/// basılı tutup başka güne sürükleyerek / menüden taşınır.
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
    /// Bakılan yer: harita ona yakınlaşır, alttan penceresi açılır.
    @State private var focusedID: UUID?
    /// Sürüklenen yerin üstünde durduğu gün.
    @State private var dropDay: Int?
    /// Yer penceresi açıkken haritanın yüksekliği: pencerenin üstünü doldurur.
    @State private var focusedMapHeight: CGFloat = 360
    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    private var days: [[Place]] { store.dayPlan(for: city) }
    private var trip: Trip { store.trip(for: city) }

    var body: some View {
        let days = self.days
        VStack(spacing: 0) {
            map(days)
                .frame(height: focusedID == nil ? 360 : max(focusedMapHeight, 360))
                .overlay(alignment: .top) { header }
                .overlay(alignment: .bottomTrailing) { MapKindMenu(selection: $mapKind).padding(12) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summary(placeCount: days.reduce(0) { $0 + $1.count })
                    ForEach(Array(days.enumerated()), id: \.offset) { index, stops in
                        daySection(index, stops: stops, dayCount: days.count)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .animation(.snappy, value: focusedID)
        .onGeometryChange(for: CGFloat.self) { proxy in
            // Yer penceresi ekranın yarısını kaplar; köşeleri de harita üstünde dursun.
            let screen = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            return screen / 2 - proxy.safeAreaInsets.top + 24
        } action: { focusedMapHeight = $0 }
        .overlay(alignment: .bottomTrailing) { addButton }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 90) }
        .animation(.snappy, value: store.undoMessage)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { $0.view }
        .sheet(isPresented: Binding(get: { focusedID != nil }, set: { if !$0 { focusedID = nil } })) {
            if let id = focusedID {
                PlaceSheet(placeID: id) { place in
                    focusedID = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(.place(place.id))
                    }
                }
                .placeSheetPresentation()
            }
        }
        .onAppear(perform: updateCamera)
        .onChange(of: selectedDay) { updateCamera() }
        .onChange(of: focusedID) { updateCamera() }
        .onChange(of: trip) { followFocusedPlace() }
        .task(id: routeKey) { await loadRoute() }
        .task { await openLaunchScreen() }
    }

    // MARK: - Harita

    private func map(_ days: [[Place]]) -> some View {
        Map(position: $position) {
            ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, stops in
                ForEach(stops) { place in
                    // Türün renkli pini (müze, kafe...) + köşede gün numarası.
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        pin(place, day: dayIndex)
                    }
                    // Bir yere bakarken yanındakilerin adları da görünsün.
                    .annotationTitles(dayIndex == selectedDay || focusedID != nil ? .visible : .hidden)
                }
            }
            if let route {
                ForEach(Array(route.polylines.enumerated()), id: \.offset) { _, line in
                    MapPolyline(line).stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .mapStyle(mapKind.exploreStyle(showingApplePlaces: false))
        // Üstteki geri düğmesi ve şehir adı pinlerin üstüne binmesin.
        .safeAreaPadding(.top, 52)
    }

    private func pin(_ place: Place, day: Int) -> some View {
        let isFocused = place.id == focusedID
        let isToday = day == selectedDay
        return Button { focus(place) } label: {
            CategoryPin(category: place.category, size: isFocused ? 40 : isToday ? 30 : 24)
                .overlay(alignment: .topTrailing) {
                    DayBadge(number: day + 1, size: isToday ? 18 : 15)
                        .offset(x: 7, y: -5)
                }
                .opacity(isToday || isFocused ? 1 : 0.55)
        }
        .buttonStyle(.plain)
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
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Liste

    /// Gün sayısı (− / +) ve yer sayısı.
    private func summary(placeCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(trip.days) gün · \(placeCount) yer").font(Theme.font(20, .bold))
                Spacer()
                stepButton("minus", label: "Gün çıkar") { store.setDays(trip.days - 1, city: city) }
                    .disabled(trip.days <= 1)
                stepButton("plus", label: "Gün ekle") { store.setDays(trip.days + 1, city: city) }
                    .disabled(trip.days >= 14)
            }
            Text("Yeri başka güne taşımak için basılı tut.")
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func daySection(_ index: Int, stops: [Place], dayCount: Int) -> some View {
        let isSelected = index == selectedDay
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                DayBadge(number: index + 1)
                    .opacity(isSelected ? 1 : 0.35)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(index + 1). gün").font(Theme.headline)
                    if isSelected, let route, !stops.isEmpty {
                        Text("\(stops.count) durak · \(Int((route.meters / 1000).rounded())) km yürüyüş")
                            .font(Theme.caption).foregroundStyle(Theme.muted)
                    } else {
                        Text("\(stops.count) durak").font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if isSelected && !stops.isEmpty {
                    Button { path.append(.walk(city: city, day: index)) } label: {
                        Label("Yürü", systemImage: "figure.walk")
                            .font(Theme.font(14, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedID = nil
                selectedDay = index
            }

            if stops.isEmpty {
                Text("Boş gün. Bir yeri basılı tutup buraya sürükle.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 10)
            }
            ForEach(stops) { place in
                row(place, day: index, dayCount: dayCount)
            }
        }
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.surface)
                .padding(.horizontal, -10)
                .opacity(dropDay == index ? 1 : 0)
        }
        .overlay(alignment: .top) { Divider() }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), let place = store.place(id) else { return false }
            store.move(place, toDay: index)
            selectedDay = index
            return true
        } isTargeted: { targeted in
            if targeted { dropDay = index } else if dropDay == index { dropDay = nil }
        }
    }

    private func row(_ place: Place, day: Int, dayCount: Int) -> some View {
        Button { focus(place) } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: place.category, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(Theme.font(15, .semibold)).lineLimit(1)
                    Text(place.category.title).font(Theme.caption).foregroundStyle(place.category.color)
                }
                Spacer(minLength: 8)
                if place.isEstimated { EstimatedTag() }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(place.id.uuidString) {
            HStack(spacing: 8) {
                CategoryIcon(category: place.category, size: 28)
                Text(place.name).font(Theme.font(15, .semibold))
            }
            .padding(10)
            .background(.white, in: Capsule())
        }
        .contextMenu {
            ForEach(0..<dayCount, id: \.self) { target in
                if target != day {
                    Button {
                        store.move(place, toDay: target)
                        selectedDay = target
                    } label: {
                        Label("\(target + 1). güne taşı", systemImage: "arrow.right.circle")
                    }
                }
            }
            Divider()
            Button(role: .destructive) { store.removeFromPlan(place) } label: {
                Label("Rotadan çıkar", systemImage: "minus.circle")
            }
        }
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var addButton: some View {
        Button { sheet = .addPlace(city: city) } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.ink, in: Circle())
                .softShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Yer ekle"))
        .padding(20)
    }

    // MARK: - Odak ve rota

    private func focus(_ place: Place) {
        if let day = store.dayIndex(of: place) { selectedDay = day }
        focusedID = place.id
    }

    /// Penceredeki gün düğmesiyle taşınan yerin gününü seçili tutar.
    private func followFocusedPlace() {
        let days = self.days
        if let id = focusedID, let day = days.firstIndex(where: { $0.contains { $0.id == id } }) {
            selectedDay = day
        } else if selectedDay >= days.count {
            selectedDay = max(days.count - 1, 0)
        }
    }

    /// Bakılan yer varsa ona ve yanındaki yerlere, yoksa seçili güne yaklaşır.
    private func updateCamera() {
        let days = self.days
        let all = days.flatMap { $0 }
        if let id = focusedID, let place = store.place(id) {
            withAnimation { position = .region(MKCoordinateRegion(focusing: place, among: all)) }
            return
        }
        let stops = days.indices.contains(selectedDay) && !days[selectedDay].isEmpty ? days[selectedDay] : all
        if let region = MKCoordinateRegion(fitting: stops.map(\.coordinate)) {
            withAnimation { position = .region(region) }
        }
    }

    private var routeKey: String {
        let days = self.days
        guard days.indices.contains(selectedDay) else { return "" }
        return days[selectedDay].map(\.id.uuidString).joined(separator: ",")
    }

    private func loadRoute() async {
        let days = self.days
        guard days.indices.contains(selectedDay) else { route = nil; return }
        route = await WalkingRoutes.route(through: days[selectedDay])
    }

    /// Yalnızca geliştirme sürümünde (ekran görüntüleri için): `-screen spot`
    /// Meiji Tapınağı'na bakar; `moved` onu başka güne taşınmış gösterir;
    /// `movedList` taşıdıktan sonra listeyi ve "Geri al" bildirimini gösterir.
    private func openLaunchScreen() async {
        #if DEBUG
        guard !Self.openedLaunchScreen else { return }
        Self.openedLaunchScreen = true
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        let all = days.flatMap { $0 }
        guard ["spot", "moved", "movedList"].contains(screen),
              let place = all.first(where: { $0.name == "Meiji Tapınağı" }) ?? all.first,
              let day = store.dayIndex(of: place) else { return }
        if screen == "movedList" { try? await Task.sleep(for: .seconds(3)) }
        if screen != "spot" {
            let target = day == 0 ? 1 : day - 1
            store.move(place, toDay: target)
            selectedDay = target
        }
        if screen != "movedList" { focus(place) }
        #endif
    }
}

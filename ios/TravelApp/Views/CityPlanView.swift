import MapKit
import SwiftUI

/// Şehir planı: yalnızca seçili gün görünür. Harita üstte (o günün türüne
/// göre renkli pinleri, sokaklardan rota), altta o günün yerleri. Gün,
/// listenin üstündeki tek "1. gün ⌄" düğmesinden değiştirilir; oradaki
/// "Tüm yerler" şehrin bütün yerlerini (köşede gün numarasıyla) gösterir. Bir yere
/// dokununca harita o yere ve yanındaki yerlere yakınlaşır, alttan yer
/// penceresi açılır; harita görünür kalır. Yer, penceredeki gün düğmesiyle
/// ya da listede basılı tutup menüden başka güne taşınır.
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
    @State private var sheetDetent: PresentationDetent = .placeHalf
    /// Alttaki listenin paneli: hangi yükseklikte (küçük, yarım, büyük) ve kaç nokta.
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 360
    @State private var screenHeight: CGFloat = 800
    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    private var days: [[Place]] { store.dayPlan(for: city) }
    private var trip: Trip { store.trip(for: city) }

    /// Gün seçicide "Tüm yerler".
    private static let allDays = -1
    private var showsAll: Bool { selectedDay == Self.allDays }

    /// Seçili günün yerleri, yürüme sırasıyla ("Tüm yerler"de hepsi, gün gün).
    private var stops: [Place] {
        let days = self.days
        if showsAll { return days.flatMap { $0 } }
        return days.indices.contains(selectedDay) ? days[selectedDay] : []
    }

    var body: some View {
        let stops = self.stops
        ZStack(alignment: .bottom) {
            map(stops)
                // Pinler haritanın görünen kısmının (panelin ya da yer
                // penceresinin üstünün) ortasında dursun.
                .safeAreaPadding(.bottom, focusedID == nil ? panelHeight + 30 : screenHeight / 2)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { header }
            if focusedID == nil {
                DraggablePanel(stops: Self.panelStops, selection: $panelStop,
                               onSettle: { panelHeight = $0 }) {
                    dayBar(stops)
                } content: {
                    list(stops)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy, value: focusedID)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        } action: { screenHeight = $0 }
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
                .placeSheetPresentation(detent: $sheetDetent)
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

    private func map(_ stops: [Place]) -> some View {
        Map(position: $position) {
            // Yalnızca seçili günün yerleri, türün renkli pini ve adıyla.
            ForEach(stops) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) { pin(place) }
            }
            // Rotadan çıkarılan yerin penceresi açıksa pini kaybolmasın.
            if let place = focusedOutsideDay {
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) { pin(place) }
            }
            if let route {
                ForEach(Array(route.polylines.enumerated()), id: \.offset) { _, line in
                    MapPolyline(line).stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            UserAnnotation()
        }
        .mapStyle(mapKind.exploreStyle(showingApplePlaces: false))
        // Üstteki geri düğmesi ve şehir adı pinlerin üstüne binmesin.
        .safeAreaPadding(.top, 52)
        // Yer penceresi uzunken haritaya dokununca pencere yarıya iner.
        .simultaneousGesture(TapGesture().onEnded {
            if focusedID != nil, sheetDetent == .placeTall { sheetDetent = .placeHalf }
        })
    }

    private var focusedOutsideDay: Place? {
        guard let id = focusedID, !stops.contains(where: { $0.id == id }) else { return nil }
        return store.place(id)
    }

    /// Türün renkli pini; "Tüm yerler"de köşesinde gün numarası.
    private func pin(_ place: Place) -> some View {
        let day = showsAll ? store.dayIndex(of: place) : nil
        return Button { focus(place) } label: {
            PlaceMapPin(place: place, size: place.id == focusedID ? 40 : 30)
                .overlay(alignment: .topTrailing) {
                    if let day {
                        DayBadge(number: day + 1, size: 16).offset(x: 7, y: -5)
                    }
                }
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
            MapKindMenu(selection: $mapKind)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Liste

    /// Panelin yükseklikleri: yalnızca gün satırı, yarım ekran, neredeyse tam ekran.
    private static let panelStops: [PanelStop] = [.height(150), .fraction(0.5), .fraction(0.9)]

    private func list(_ stops: [Place]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if stops.isEmpty {
                Text(showsAll ? LocalizedStringKey("Rotada henüz yer yok. Sağ alttaki + ile yer ekle.")
                              : LocalizedStringKey("Bu gün boş. Sağ alttaki + ile yer ekle."))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 14)
            }
            if showsAll {
                ForEach(Array(days.enumerated()), id: \.offset) { index, places in
                    if !places.isEmpty {
                        Text("\(index + 1). gün")
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 14)
                            .padding(.bottom, 2)
                        ForEach(places) { place in row(place) }
                    }
                }
            } else {
                ForEach(stops) { place in row(place) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
    }

    /// Listenin üstünde tek satır: gün seçici, o günün özeti ve Yürü.
    private func dayBar(_ stops: [Place]) -> some View {
        HStack(spacing: 10) {
            dayMenu
            Group {
                if showsAll {
                    Text("\(stops.count) yer")
                } else if let route, !stops.isEmpty {
                    Text("\(stops.count) durak · \(Int((route.meters / 1000).rounded())) km")
                } else {
                    Text("\(stops.count) durak")
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            Spacer(minLength: 4)
            if !stops.isEmpty && !showsAll {
                Button { path.append(.walk(city: city, day: selectedDay)) } label: {
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
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// "1. gün ⌄": günler (kaçar yer), Tüm yerler, Gün ekle, Son günü sil.
    private var dayMenu: some View {
        let days = self.days
        return Menu {
            Picker("Gün", selection: Binding(get: { selectedDay }, set: { day in
                focusedID = nil
                selectedDay = day
            })) {
                ForEach(days.indices, id: \.self) { day in
                    Text("\(day + 1). gün · \(days[day].count) yer").tag(day)
                }
                Text("Tüm yerler · \(days.reduce(0) { $0 + $1.count }) yer").tag(Self.allDays)
            }
            .pickerStyle(.inline)
            Section {
                Button {
                    store.setDays(trip.days + 1, city: city)
                    focusedID = nil
                    selectedDay = trip.days - 1
                } label: {
                    Label("Gün ekle", systemImage: "plus")
                }
                .disabled(trip.days >= 14)
                Button(role: .destructive) { store.setDays(trip.days - 1, city: city) } label: {
                    Label("Son günü sil", systemImage: "trash")
                }
                .disabled(trip.days <= 1)
            }
        } label: {
            HStack(spacing: 6) {
                Text(showsAll ? LocalizedStringKey("Tüm yerler") : LocalizedStringKey("\(selectedDay + 1). gün"))
                    .font(Theme.font(17, .bold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityHint(Text("Günü değiştir"))
    }

    /// Listede bir yer ("Add a spot" gibi): solda fotoğraf (köşesinde türün
    /// simgesi), yanında tür ve ad; adını hatırlamayan fotoğraftan tanır.
    private func row(_ place: Place) -> some View {
        Button { focus(place) } label: {
            HStack(spacing: 14) {
                PlaceRowThumbnail(place: place)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.category.title)
                        .font(Theme.font(11, .bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(place.category.color)
                    Text(place.name).font(Theme.font(16, .semibold)).lineLimit(2)
                }
                Spacer(minLength: 8)
                if place.isEstimated { EstimatedTag() }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(0..<trip.days, id: \.self) { target in
                if target != store.dayIndex(of: place) {
                    Button { store.move(place, toDay: target) } label: {
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

    private var addButton: some View {
        Button { sheet = .addPlace(city: city, day: max(selectedDay, 0)) } label: {
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
        if !showsAll, let day = store.dayIndex(of: place) { selectedDay = day }
        sheetDetent = .placeHalf
        focusedID = place.id
    }

    /// Penceredeki gün düğmesiyle taşınan yerin yeni gününe geçer ("Tüm yerler"de kalır).
    private func followFocusedPlace() {
        if showsAll { return }
        if let id = focusedID, let place = store.place(id), let day = store.dayIndex(of: place) {
            selectedDay = day
        } else if selectedDay >= trip.days {
            selectedDay = max(trip.days - 1, 0)
        }
    }

    /// Bakılan yer varsa ona ve günün yanındaki yerlerine, yoksa seçili
    /// güne (boşsa bütün rotaya) yaklaşır.
    private func updateCamera() {
        let stops = self.stops
        if let id = focusedID, let place = store.place(id) {
            withAnimation { position = .region(MKCoordinateRegion(focusing: place, among: stops)) }
            return
        }
        let shown = stops.isEmpty ? days.flatMap { $0 } : stops
        if let region = MKCoordinateRegion(fitting: shown.map(\.coordinate)) {
            withAnimation { position = .region(region) }
        } else if let center = store.center(of: city) {
            // Henüz yeri olmayan şehir (gezide yeni eklenen): şehrin ortası.
            position = .region(MKCoordinateRegion(center: center, latitudinalMeters: 15_000, longitudinalMeters: 15_000))
        }
    }

    private var routeKey: String {
        "\(selectedDay)|" + stops.map(\.id.uuidString).joined(separator: ",")
    }

    /// Seçili günün yürüme yolu ("Tüm yerler"de yol çizilmez).
    private func loadRoute() async {
        let stops = self.stops
        guard !stops.isEmpty, !showsAll else { route = nil; return }
        route = await WalkingRoutes.route(through: stops)
    }

    /// Yalnızca geliştirme sürümünde (ekran görüntüleri için): `-screen spot`
    /// Meiji Tapınağı'na bakar; `moved` onu başka güne taşınmış gösterir;
    /// `movedList` taşıdıktan sonra yeni gününün listesini ve "Geri al"
    /// bildirimini gösterir; `photo` fotoğrafı tam ekran, `sheetTall`
    /// pencereyi uzun açar; `all` bütün yerleri gösterir; `cityTall` listenin
    /// panelini yukarı çekilmiş gösterir.
    private func openLaunchScreen() async {
        #if DEBUG
        guard !Self.openedLaunchScreen else { return }
        Self.openedLaunchScreen = true
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        let all = days.flatMap { $0 }
        if screen == "all" { selectedDay = Self.allDays }
        if screen == "cityTall" { panelStop = Self.panelStops.count - 1 }
        guard ["spot", "moved", "movedList", "photo", "sheetTall", "listen"].contains(screen),
              let place = all.first(where: { $0.name == "Meiji Tapınağı" }) ?? all.first,
              let day = store.dayIndex(of: place) else { return }
        if screen == "movedList" { try? await Task.sleep(for: .seconds(3)) }
        if screen == "moved" || screen == "movedList" {
            let target = day == 0 ? 1 : day - 1
            store.move(place, toDay: target)
            selectedDay = target
        }
        if screen != "movedList" { focus(place) }
        if screen == "sheetTall" {
            try? await Task.sleep(for: .seconds(1.5))
            sheetDetent = .placeTall
        }
        if screen == "listen" {
            try? await Task.sleep(for: .seconds(1))
            Narrator.shared.speak("Meiji Tapınağı, Tokyo'nun Shibuya semtinde bulunan bir Şinto tapınağıdır. "
                                  + "Tapınak İmparator Meiji ile İmparatoriçe Shōken'in ruhlarına adanmıştır.",
                                  title: place.name, language: "tr")
            try? await Task.sleep(for: .seconds(2))
            Narrator.shared.togglePause()
        }
        #endif
    }
}

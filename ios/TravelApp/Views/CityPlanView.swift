import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// Şehir planı: yalnızca seçili gün görünür. Harita üstte (o günün türüne
/// göre renkli pinleri, sokaklardan rota), altta o günün yerleri. Gün,
/// listenin üstündeki tek "1. gün ⌄" düğmesinden değiştirilir; oradaki
/// "Tüm yerler" şehrin bütün yerlerini (köşede gün numarasıyla) gösterir. Bir yere
/// dokununca harita o yere ve yanındaki yerlere yakınlaşır, alttan yer
/// penceresi açılır; harita görünür kalır. Listede basılı tutup sürükleyerek
/// sıra (ve "Tüm yerler"de gün) değişir; basılı tutunca açılan menüde not,
/// düzenleme, güne taşıma ve rotadan çıkarma var. Her gezinin şehri kendi
/// planını tutar.
struct CityPlanView: View {
    /// Gezideki şehir (`Destination.id`).
    let stopID: UUID
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var mapFocus: MapFocus?
    /// Haritanın yakınlığı: yaklaşınca pinlerin adları da yazılır.
    @State private var zoom: Float = 12
    @AppStorage(PinStyle.storageKey) private var pinStyle = PinStyle.icon
    @ObservedObject private var pinPhotos = PinPhotos.shared
    @State private var selectedDay = 0
    @State private var route: WalkingRoutes.DayRoute?
    @State private var sheet: AddSheet?
    /// Bakılan yer: harita ona yakınlaşır, alttan penceresi açılır.
    @State private var focusedID: UUID?
    /// Haritada dokunulan Google yeri (restoran, müze...): penceresi açık.
    @State private var googlePlace: GooglePlaceRef?
    @State private var sheetDetent: PresentationDetent = .placeHalf
    /// Alttaki listenin paneli: hangi yükseklikte (küçük, yarım, büyük) ve kaç nokta.
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 360
    @State private var screenHeight: CGFloat = 800
    /// Basılı tutup sürüklenen yer ve bırakılacağı yer (satırın üstü/altı).
    @State private var draggedID: UUID?
    @State private var dropSlot: DropSlot?
    /// Düzenlenen yer (ad, tür, not).
    @State private var editing: Place?
    @State private var editsNote = false
    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    private var city: String { store.stop(stopID)?.stop.city ?? "" }
    private var days: [[Place]] { store.dayPlan(stop: stopID) }
    private var trip: Trip { store.trip(stop: stopID) }

    /// Gün seçicide "Tüm yerler".
    private static let allDays = -1
    private var showsAll: Bool { selectedDay == Self.allDays }

    /// Seçili günün yerleri, yürüme sırasıyla ("Tüm yerler"de hepsi, gün gün).
    private var stops: [Place] {
        let days = self.days
        if showsAll { return days.flatMap { $0 } }
        return days.indices.contains(selectedDay) ? days[selectedDay] : []
    }

    /// Yer penceresi açık (kayıtlı yer ya da Google'ın yeri): liste paneli iner.
    private var showsPlaceSheet: Bool { focusedID != nil || googlePlace != nil }

    var body: some View {
        let stops = self.stops
        ZStack(alignment: .bottom) {
            map(stops)
                .ignoresSafeArea()
                .overlay(alignment: .top) { header }
        }
        .slidingPanel(stops: Self.panelStops, selection: $panelStop, isHidden: showsPlaceSheet,
                      onSettle: { panelHeight = $0 }) {
            dayBar(stops)
        } content: {
            list(stops)
        }
        .animation(.snappy, value: showsPlaceSheet)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        } action: { screenHeight = $0 }
        .overlay(alignment: .bottomTrailing) { addButton }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 90) }
        .animation(.snappy, value: store.undoMessage)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { $0.view }
        .sheet(item: $editing) { PlaceEditor(place: $0, focusesNote: editsNote) }
        .sheet(isPresented: Binding(get: { focusedID != nil }, set: { if !$0 { focusedID = nil } })) {
            if let id = focusedID {
                PlaceSheet(placeID: id, stop: stopID) { place in
                    focusedID = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(.place(place.id))
                    }
                }
                .placeSheetPresentation(detent: $sheetDetent)
            }
        }
        .sheet(item: $googlePlace) { place in
            GooglePlaceSheet(place: place) { saved in
                // Kaydedilen yerin kendi penceresi (gün düğmesiyle rotaya eklenir).
                googlePlace = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    focus(saved)
                }
            }
            .placeSheetPresentation(detent: $sheetDetent)
        }
        .onAppear(perform: updateCamera)
        .onChange(of: selectedDay) { updateCamera() }
        .onChange(of: focusedID) { updateCamera() }
        .onChange(of: trip) { followFocusedPlace() }
        .task(id: routeKey) { await loadRoute() }
        .task(id: "\(pinStyle)|\(routeKey)") {
            if pinStyle == .photo { pinPhotos.load(stops + days.flatMap { $0 }) }
        }
        .task { await openLaunchScreen() }
    }

    // MARK: - Harita

    private func map(_ stops: [Place]) -> some View {
        // Yalnızca seçili günün yerleri; rotadan çıkarılan yerin penceresi
        // açıksa pini kaybolmasın.
        let shown = stops + (focusedOutsideDay.map { [$0] } ?? [])
        let showsTitles = zoom >= 14 || shown.count <= 15
        let markers = shown.map { place in
            GoogleMap.Marker.place(place, size: place.id == focusedID ? 40 : 30,
                                   photo: pinStyle == .photo ? pinPhotos.image(for: place) : nil,
                                   day: showsAll ? store.dayIndex(of: place, stop: stopID) : nil,
                                   showsTitle: showsTitles || place.id == focusedID,
                                   zIndex: place.id == focusedID ? 1 : 0) { focus(place) }
        }
        let lines = (route?.lines ?? []).enumerated().map { index, line in
            GoogleMap.Line(id: "route-\(index)", coordinates: line, color: UIColor(Theme.accent))
        }
        // Pinler haritanın görünen kısmının (üstteki düğmelerin altı ile
        // panelin ya da yer penceresinin üstü arası) ortasında dursun.
        return GoogleMap(focus: $mapFocus, markers: markers, lines: lines,
                         padding: EdgeInsets(top: 52, leading: 0,
                                             bottom: showsPlaceSheet ? screenHeight / 2 - 20 : panelHeight,
                                             trailing: 0),
                         onPlaceTap: { id, name, coordinate in showGooglePlace(id: id, name: name, coordinate: coordinate) },
                         onMapTap: {
                             // Yer penceresi uzunken haritaya dokununca pencere yarıya iner.
                             if showsPlaceSheet, sheetDetent == .placeTall { sheetDetent = .placeHalf }
                         },
                         onCameraIdle: { zoom = $0.zoom })
    }

    private var focusedOutsideDay: Place? {
        guard let id = focusedID, !stops.contains(where: { $0.id == id }) else { return nil }
        return store.place(id)
    }

    private var header: some View {
        HStack(alignment: .top) {
            CircleIconButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            Text(city)
                .font(Theme.font(17, .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: Capsule())
                .softShadow()
            Spacer()
            MapControls(focus: $mapFocus)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Liste

    /// Panelin yükseklikleri: yalnızca gün satırı, yarım ekran, neredeyse tam ekran.
    private static let panelStops: [PanelStop] = [.height(150), .fraction(0.5), .fraction(0.9)]

    private func list(_ stops: [Place]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAll {
                // Bütün günler (boş günler de): yer başka günün başlığına
                // sürüklenince o günün sonuna geçer.
                ForEach(Array(days.enumerated()), id: \.offset) { index, places in
                    dayHeader(index, isEmpty: places.isEmpty)
                    ForEach(places) { place in row(place, day: index) }
                }
            } else {
                if stops.isEmpty {
                    Text("Bu gün boş. Sağ alttaki + ile yer ekle.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 14)
                } else if stops.count > 1 {
                    Text(store.isManuallyOrdered(day: selectedDay, stop: stopID)
                         ? LocalizedStringKey("Senin sıran. Sırayı değiştirmek için basılı tutup sürükle.")
                         : LocalizedStringKey("Yürüme sırası. Sırayı değiştirmek için basılı tutup sürükle."))
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                    row(place, day: selectedDay, number: index + 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
        .animation(.snappy, value: stops.map(\.id))
    }

    /// "Tüm yerler"de günün başlığı; üstüne bırakılan yer o güne geçer.
    private func dayHeader(_ day: Int, isEmpty: Bool) -> some View {
        let targeted = dropSlot == DropSlot(target: nil, day: day, after: true)
        return HStack(spacing: 8) {
            Text("\(day + 1). gün").font(Theme.font(13, .bold)).foregroundStyle(Theme.muted)
            if isEmpty {
                Text("Boş gün").font(Theme.font(12)).foregroundStyle(Theme.muted.opacity(0.7))
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(targeted ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, -8)
        .padding(.top, 8)
        .onDrop(of: [.text], delegate: RowDrop(target: nil, day: day, current: $dropSlot) { _ in
            drop(before: nil, day: day)
        })
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
                Button { path.append(.walk(stop: stopID, day: selectedDay)) } label: {
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
                    store.setDays(trip.days + 1, stop: stopID)
                    focusedID = nil
                    selectedDay = trip.days - 1
                } label: {
                    Label("Gün ekle", systemImage: "plus")
                }
                .disabled(trip.days >= 14)
                Button(role: .destructive) { store.setDays(trip.days - 1, stop: stopID) } label: {
                    Label("Son günü sil", systemImage: "trash")
                }
                .disabled(trip.days <= 1)
            }
            if !showsAll && store.isManuallyOrdered(day: selectedDay, stop: stopID) {
                Button { withAnimation(.snappy) { store.orderByWalking(day: selectedDay, stop: stopID) } } label: {
                    Label("Yürüme sırasına diz", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
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
    /// simgesi), yanında tür, ad ve notun; sağda sürükleme tutamağı.
    /// Basılı tutunca menü açılır; menü açıkken sürükleyince yer taşınır.
    private func row(_ place: Place, day: Int, number: Int? = nil) -> some View {
        let slot = dropSlot?.target == place.id ? dropSlot : nil
        return Button { focus(place) } label: {
            HStack(spacing: 14) {
                PlaceRowThumbnail(place: place)
                    .overlay(alignment: .topLeading) {
                        if let number {
                            Text("\(number)")
                                .font(Theme.font(11, .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Theme.ink, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                .offset(x: -6, y: -6)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.category.title)
                        .font(Theme.font(11, .bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(place.category.color)
                    Text(place.name).font(Theme.font(16, .semibold)).lineLimit(2)
                    if !place.note.isEmpty {
                        Label(place.note, systemImage: "note.text")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if place.isEstimated { EstimatedTag() }
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.hairline)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(draggedID == place.id && dropSlot != nil ? 0.4 : 1)
        .overlay(alignment: slot?.after == true ? .bottom : .top) {
            if slot != nil {
                Capsule().fill(Theme.ink).frame(height: 3).offset(y: slot?.after == true ? 2 : -2)
            }
        }
        .onDrag {
            draggedID = place.id
            return NSItemProvider(object: place.id.uuidString as NSString)
        } preview: {
            HStack(spacing: 10) {
                PlaceRowThumbnail(place: place, size: 40)
                Text(place.name).font(Theme.font(15, .semibold)).lineLimit(1)
            }
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .onDrop(of: [.text], delegate: RowDrop(target: place.id, day: day, current: $dropSlot) { after in
            drop(on: place, day: day, after: after)
        })
        .contextMenu { menu(place, day: day) }
        .accessibilityAction(named: Text("Yukarı taşı")) { shift(place, day: day, by: -1) }
        .accessibilityAction(named: Text("Aşağı taşı")) { shift(place, day: day, by: 1) }
    }

    /// Basılı tutunca: not, düzenle, sıra, güne taşı, rotadan çıkar.
    @ViewBuilder
    private func menu(_ place: Place, day: Int) -> some View {
        Button {
            editsNote = true
            editing = place
        } label: {
            Label(place.note.isEmpty ? LocalizedStringKey("Not ekle") : LocalizedStringKey("Notu düzenle"),
                  systemImage: "square.and.pencil")
        }
        Button {
            editsNote = false
            editing = place
        } label: {
            Label("Düzenle", systemImage: "pencil")
        }
        let list = days.indices.contains(day) ? days[day] : []
        if list.count > 1 {
            Section {
                if list.first?.id != place.id {
                    Button { shift(place, day: day, by: -1) } label: { Label("Yukarı taşı", systemImage: "arrow.up") }
                }
                if list.last?.id != place.id {
                    Button { shift(place, day: day, by: 1) } label: { Label("Aşağı taşı", systemImage: "arrow.down") }
                }
            }
        }
        if trip.days > 1 {
            Section("Güne taşı") {
                ForEach(0..<trip.days, id: \.self) { target in
                    Button { move(place, toDay: target) } label: {
                        if target == day {
                            Label("\(target + 1). gün", systemImage: "checkmark")
                        } else {
                            Text("\(target + 1). gün")
                        }
                    }
                    .disabled(target == day)
                }
            }
        }
        Section {
            Button(role: .destructive) { store.removeFromPlan(place, stop: stopID) } label: {
                Label("Rotadan çıkar", systemImage: "minus.circle")
            }
        }
    }

    private var addButton: some View {
        Button { sheet = .addPlace(city: city, stop: stopID, day: max(selectedDay, 0)) } label: {
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

    // MARK: - Sıra ve gün

    /// Sürüklenen yer bir satırın üst ya da alt yarısına bırakıldı.
    private func drop(on target: Place, day: Int, after: Bool) {
        let list = days.indices.contains(day) ? days[day] : []
        guard target.id != draggedID, let index = list.firstIndex(where: { $0.id == target.id }) else {
            draggedID = nil
            return
        }
        let next = list[(index + 1)...].first { $0.id != draggedID }
        drop(before: after ? next : target, day: day)
    }

    /// Sürüklenen yeri `target`ın önüne (yoksa günün sonuna) koyar.
    private func drop(before target: Place?, day: Int) {
        defer { draggedID = nil }
        guard let id = draggedID, let place = store.place(id), target?.id != id else { return }
        withAnimation(.snappy) { store.reorder(place, before: target, day: day, stop: stopID) }
    }

    /// Menüden (ya da VoiceOver ile) bir yukarı / bir aşağı.
    private func shift(_ place: Place, day: Int, by offset: Int) {
        let list = days.indices.contains(day) ? days[day] : []
        guard let index = list.firstIndex(where: { $0.id == place.id }), list.indices.contains(index + offset) else { return }
        let before: Place? = offset < 0 ? list[index + offset]
                                        : list.indices.contains(index + offset + 1) ? list[index + offset + 1] : nil
        withAnimation(.snappy) { store.reorder(place, before: before, day: day, stop: stopID) }
    }

    private func move(_ place: Place, toDay day: Int) {
        withAnimation(.snappy) { store.move(place, toDay: day, stop: stopID) }
    }

    // MARK: - Odak ve rota

    private func focus(_ place: Place) {
        if !showsAll, let day = store.dayIndex(of: place, stop: stopID) { selectedDay = day }
        sheetDetent = .placeHalf
        focusedID = place.id
    }

    /// Haritada Google'ın bir yerine dokunuldu: kayıtlıysa kendi penceresi,
    /// değilse Google'ın bilgileriyle pencere (Kaydet, yol tarifi).
    private func showGooglePlace(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        let name = name.replacingOccurrences(of: "\n", with: " ")
        if let saved = store.savedPlace(googleID: id, named: name, near: coordinate) {
            focus(saved)
            return
        }
        focusedID = nil
        sheetDetent = .placeHalf
        googlePlace = GooglePlaceRef(id: id, name: name, coordinate: coordinate)
    }

    /// Penceredeki gün düğmesiyle taşınan yerin yeni gününe geçer ("Tüm yerler"de kalır).
    private func followFocusedPlace() {
        if showsAll { return }
        if let id = focusedID, let place = store.place(id), let day = store.dayIndex(of: place, stop: stopID) {
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
            mapFocus = .region(MKCoordinateRegion(focusing: place, among: stops))
            return
        }
        let shown = stops.isEmpty ? days.flatMap { $0 } : stops
        if let region = MKCoordinateRegion(fitting: shown.map(\.coordinate)) {
            mapFocus = .region(region, animated: mapFocus != nil)
        } else if let center = store.center(of: city) {
            // Henüz yeri olmayan şehir (gezide yeni eklenen): şehrin ortası.
            mapFocus = .region(MKCoordinateRegion(center: center, latitudinalMeters: 15_000, longitudinalMeters: 15_000),
                            animated: false)
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
    /// panelini yukarı çekilmiş gösterir; `reorder` 1. günü elle sıralanmış
    /// ve ilk yeri notlu gösterir; `editPlace` yeri düzenleme penceresini açar.
    private func openLaunchScreen() async {
        #if DEBUG
        // Ekran yerleşsin; açılışta yeniden kurulan görünüm (iptal edilen
        // görev) sırayı kullanmasın.
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, !Self.openedLaunchScreen else { return }
        Self.openedLaunchScreen = true
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        let all = days.flatMap { $0 }
        if screen == "all" { selectedDay = Self.allDays }
        if screen == "cityTall" { panelStop = Self.panelStops.count - 1 }
        if screen == "reorder" || screen == "editPlace", let firstDay = days.first, firstDay.count > 1,
           let last = firstDay.last {
            store.reorder(last, before: firstDay.first, day: 0, stop: stopID)
            if var noted = store.place(last.id) {
                noted.note = "Sabah erken git, sıra oluyor"
                store.update(noted)
            }
            store.dismissUndo()
            if screen == "reorder" { panelStop = Self.panelStops.count - 1 }
            if screen == "editPlace", let place = store.place(last.id) {
                editsNote = false
                editing = place
            }
            return
        }
        guard ["spot", "moved", "movedList", "photo", "sheetTall", "listen"].contains(screen),
              let place = all.first(where: { $0.name == "Meiji Tapınağı" }) ?? all.first,
              let day = store.dayIndex(of: place, stop: stopID) else { return }
        if screen == "movedList" { try? await Task.sleep(for: .seconds(3)) }
        if screen == "moved" || screen == "movedList" {
            let target = day == 0 ? 1 : day - 1
            store.move(place, toDay: target, stop: stopID)
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

/// Sürüklenen yerin bırakılacağı yer: bir satırın üstü ya da altı; "Tüm
/// yerler"de günün başlığı (`target` nil, günün sonu).
private struct DropSlot: Equatable {
    var target: UUID?
    var day: Int
    var after: Bool
}

/// Satıra ya da gün başlığına sürüklenen yer: parmak satırın üst ya da alt
/// yarısındaysa oraya çizgi çizilir; bırakınca yer taşınır.
private struct RowDrop: DropDelegate {
    let target: UUID?
    let day: Int
    @Binding var current: DropSlot?
    let perform: (_ after: Bool) -> Void

    /// Satırın yaklaşık yarısı (fotoğraf 56 + boşluklar).
    private static let half: CGFloat = 36

    private func slot(_ info: DropInfo) -> DropSlot {
        DropSlot(target: target, day: day, after: target == nil || info.location.y > Self.half)
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }

    func dropEntered(info: DropInfo) { current = slot(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = slot(info)
        if current != next { current = next }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if current?.target == target && current?.day == day { current = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = slot(info).after
        current = nil
        perform(after)
        return true
    }
}

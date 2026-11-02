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
    /// Günün sırası penceresi (Akıllı sıra / En kısa yol).
    @State private var ordering: OrderRequest?
    /// Saati belirlenen yer (ör. restoran 14:00).
    @State private var timing: Place?
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
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, showsPlaceSheet ? 16 : min(panelHeight, 200) + 8) }
        .animation(.snappy, value: store.undoMessage)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { $0.view }
        .sheet(item: $editing) { PlaceEditor(place: $0, focusesNote: editsNote) }
        .sheet(item: $ordering) { request in
            DayOrderSheet(stopID: stopID, day: request.day, mode: request.mode, message: request.message)
        }
        .sheet(item: $timing) { place in
            TimePinSheet(place: place, stopID: stopID) { minutes in suggestOrder(after: place, minutes: minutes) }
        }
        // Yere dokununca ayrıntının tamamı doğrudan bu pencerede ("Aç" adımı
        // yok); üstte harita görünür kalır.
        .sheet(isPresented: Binding(get: { focusedID != nil }, set: { if !$0 { focusedID = nil } })) {
            if let id = focusedID {
                PlaceSheet(placeID: id, stop: stopID, fallbackDay: max(selectedDay, 0))
                    .placeSheetPresentation(detent: $sheetDetent)
            }
        }
        .sheet(item: $googlePlace) { place in
            GooglePlaceSheet(place: place, context: .cityPlan(stop: stopID, day: nil, fallback: max(selectedDay, 0))) { saved in
                // Rotaya eklenen ya da kaydedilen yerin kendi penceresi.
                googlePlace = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    focus(saved, detent: sheetDetent)
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
                                             bottom: showsPlaceSheet ? screenHeight * sheetDetent.placeFraction - 20
                                                                     : panelHeight,
                                             trailing: 0),
                         onPlaceTap: { id, name, coordinate in showGooglePlace(id: id, name: name, coordinate: coordinate) },
                         onMapTap: {
                             // Yer penceresi uzunken haritaya dokununca pencere yarıya iner.
                             if showsPlaceSheet, sheetDetent != .placeHalf { sheetDetent = .placeHalf }
                         },
                         onCameraIdle: { zoom = $0.zoom })
    }

    private var focusedOutsideDay: Place? {
        guard let id = focusedID, !stops.contains(where: { $0.id == id }) else { return nil }
        return store.place(id)
    }

    /// Üst çubuk: geri, ortada "İstanbul · 1. gün ⌄" (günler arası geçiş,
    /// Apple Haritalar sadeliğinde), sağda harita düğmeleri. Liste tam
    /// ekrandayken çubuk beyaz zeminli olur.
    private var header: some View {
        let fullScreen = panelStop == Self.panelStops.count - 1 && !showsPlaceSheet
        return HStack(alignment: .top) {
            CircleIconButton(systemImage: "chevron.left") { dismiss() }
                .accessibilityLabel(Text("Geri"))
            Spacer()
            dayMenu
            Spacer()
            MapControls(focus: $mapFocus)
                .opacity(fullScreen ? 0 : 1)
                .allowsHitTesting(!fullScreen)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            if fullScreen { Color.white.ignoresSafeArea(edges: .top) }
        }
        .animation(.snappy, value: fullScreen)
    }

    // MARK: - Liste

    /// Panelin yükseklikleri: yalnızca gün satırı, yarım ekran, tam ekran
    /// (üst çubuk görünür kalır).
    private static let panelStops: [PanelStop] = [.height(96), .fraction(0.5), .belowTop(60)]

    private func list(_ stops: [Place]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAll {
                // Bütün günler (boş günler de): yer başka günün başlığına
                // sürüklenince o günün sonuna geçer.
                ForEach(Array(days.enumerated()), id: \.offset) { index, places in
                    dayHeader(index, isEmpty: places.isEmpty)
                    if !places.isEmpty {
                        spotsCard { ForEach(places) { place in row(place, day: index) } }
                    }
                }
            } else {
                if stops.isEmpty {
                    Text("Bu gün boş. Haritada bir yere dokunup rotaya ekleyebilir ya da aşağıdan arayabilirsin.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 14)
                } else if stops.count > 1 {
                    Text(orderHint)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                }
                let times = schedule(stops)
                if !stops.isEmpty {
                    spotsCard {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                            row(place, day: selectedDay, number: index + 1, time: times[place.id])
                        }
                    }
                }
            }
            addRow.padding(.top, 6)
            PopularStrip(city: city, stopID: stopID, day: showsAll ? nil : selectedDay)
                .padding(.horizontal, -20)
                .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
        .animation(.snappy, value: stops.map(\.id))
    }

    /// Günün yerleri tek yuvarlak kartın içinde (Polarsteps "Spots" gibi).
    private func spotsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .padding(.top, 6)
    }

    private var orderHint: LocalizedStringKey {
        if store.isSmartOrdered(day: selectedDay, stop: stopID) {
            return "Akıllı sıra: tahmini saatler 09:00'dan. Değiştirmek için basılı tutup sürükle."
        }
        return store.isManuallyOrdered(day: selectedDay, stop: stopID)
            ? "Senin sıran. Sırayı değiştirmek için basılı tutup sürükle."
            : "En kısa yol. Sırayı değiştirmek için basılı tutup sürükle."
    }

    /// Günün tahmini saatleri: gün akıllı sıradaysa ya da bir yere saat
    /// verildiyse görünür (yoksa boş).
    private func schedule(_ stops: [Place]) -> [UUID: DayPlanner.Entry] {
        let dayStops = store.dayStops(stops, stop: stopID)
        guard store.isSmartOrdered(day: selectedDay, stop: stopID) || dayStops.contains(where: { $0.pinned != nil })
        else { return [:] }
        let entries = DayPlanner.schedule(dayStops, walkingMinutes: route.map { Double($0.minutes) })
        return Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
    }

    /// Yere saat verildi: gün o saate göre dizilsin diye öneri penceresi açılır.
    private func suggestOrder(after place: Place, minutes: Int?) {
        guard let minutes, let day = store.dayIndex(of: place, stop: stopID),
              days.indices.contains(day), days[day].count > 1 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            ordering = OrderRequest(day: day, mode: .smart,
                                    message: String(localized: "\(place.name) saat \(DayPlanner.clock(minutes)) olarak ayarlandı. Günün geri kalanı buna göre:"))
        }
    }

    /// Listenin sonunda "+ Yer ekle" (Polarsteps "Add a spot" gibi).
    private var addRow: some View {
        Button { openAddPlace() } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                Text("Yer ekle").font(Theme.font(16, .semibold))
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openAddPlace() {
        sheet = .addPlace(city: city, stop: stopID, day: max(selectedDay, 0))
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

    /// Listenin üstünde tek satır: günün adı ve özeti, + (yer ekle) ve Yürü.
    /// Gün, haritanın üstündeki "İstanbul · 1. gün ⌄" düğmesinden değişir.
    private func dayBar(_ stops: [Place]) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(showsAll ? LocalizedStringKey("Tüm yerler") : LocalizedStringKey("\(selectedDay + 1). gün"))
                    .font(Theme.font(19, .bold))
                Group {
                    if showsAll {
                        Text("\(stops.count) yer")
                    } else if !stops.isEmpty {
                        Text(daySummary(stops))
                    } else {
                        Text("\(stops.count) durak")
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                // "5 durak · 8,6 km · yaklaşık 12 sa 55 dk" kesilmesin.
                .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 4)
            Button { openAddPlace() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Yer ekle"))
            if !stops.isEmpty && !showsAll {
                Button { path.append(.walk(stop: stopID, day: selectedDay)) } label: {
                    Label("Yürü", systemImage: "figure.walk")
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// "5 durak · 6 km · yaklaşık 4 sa 30 dk": yürüme (Google yürüyüş
    /// rotası) ve her yerin gezme süresi (türüne göre ya da kullanıcının verdiği).
    private func daySummary(_ stops: [Place]) -> String {
        let dayStops = store.dayStops(stops, stop: stopID)
        let walking = route.map { Double($0.minutes) }
        let total = DayPlanner.totalMinutes(dayStops, walkingMinutes: walking)
        let meters = route?.meters ?? DayPlanner.legMinutes(dayStops).reduce(0, +) * 80
        let kilometers = (meters / 1000).formatted(.number.precision(.fractionLength(meters < 10_000 ? 1 : 0)))
        return String(localized: "\(stops.count) durak · \(kilometers) km · yaklaşık \(DayPlanner.durationText(total))")
    }

    /// Haritanın üstündeki "İstanbul · 1. gün ⌄": günler (kaçar yer), Tüm
    /// yerler, Gün ekle, Son günü sil, günü başka günle değiştir, yürüme sırası.
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
            if !showsAll && days.indices.contains(selectedDay) && days[selectedDay].count > 1 {
                orderSection
            }
            Section {
                Button {
                    store.setDays(trip.days + 1, stop: stopID)
                    focusedID = nil
                    selectedDay = trip.days - 1
                } label: {
                    Label("Gün ekle", systemImage: "plus")
                }
                .disabled(trip.days >= 14)
                if !showsAll && trip.days > 1 {
                    Menu {
                        ForEach(0..<trip.days, id: \.self) { other in
                            if other != selectedDay {
                                Button("\(other + 1). günle yer değiştir") { swapDay(with: other) }
                            }
                        }
                    } label: {
                        Label("Bu günü taşı", systemImage: "arrow.up.arrow.down")
                    }
                }
                Button(role: .destructive) { store.setDays(trip.days - 1, stop: stopID) } label: {
                    Label("Son günü sil", systemImage: "trash")
                }
                .disabled(trip.days <= 1)
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: city).font(Theme.font(17, .bold)).lineLimit(1)
                Text(showsAll ? LocalizedStringKey("Tüm yerler") : LocalizedStringKey("\(selectedDay + 1). gün"))
                    .font(Theme.font(17, .regular))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(.white, in: Capsule())
            .softShadow()
        }
        .menuOrder(.fixed)
        .accessibilityHint(Text("Günü değiştir"))
    }

    /// Günün sırası: Akıllı sıra (öneri penceresi), En kısa yol, Benim sıram
    /// (şu anki sıra sabitlenir). Seçili olanın yanında ✓.
    private var orderSection: some View {
        let smart = store.isSmartOrdered(day: selectedDay, stop: stopID)
        let manual = store.isManuallyOrdered(day: selectedDay, stop: stopID)
        return Section("Sıra") {
            Button { ordering = OrderRequest(day: selectedDay, mode: .smart) } label: {
                Label("Akıllı sıra…", systemImage: smart ? "checkmark" : "sparkles")
            }
            Button {
                withAnimation(.snappy) { store.orderByWalking(day: selectedDay, stop: stopID) }
            } label: {
                Label("En kısa yol", systemImage: !manual ? "checkmark" : "point.topleft.down.to.point.bottomright.curvepath")
            }
            Button {
                if !manual || smart { store.keepOrder(day: selectedDay, stop: stopID) }
            } label: {
                Label("Benim sıram", systemImage: manual && !smart ? "checkmark" : "hand.draw")
            }
        }
    }

    /// Bakılan günün bütün planı başka günle yer değiştirir; o güne geçilir.
    private func swapDay(with other: Int) {
        let current = selectedDay
        withAnimation(.snappy) {
            store.swapDays(current, other, stop: stopID)
            selectedDay = other
        }
    }

    /// Listede bir yer ("Add a spot" gibi): solda fotoğraf (köşesinde türün
    /// simgesi), yanında tür, ad ve notun; sağda sürükleme tutamağı.
    /// Basılı tutunca menü açılır; menü açıkken sürükleyince yer taşınır.
    private func row(_ place: Place, day: Int, number: Int? = nil, time: DayPlanner.Entry? = nil) -> some View {
        let slot = dropSlot?.target == place.id ? dropSlot : nil
        return Button { focus(place, detent: .placeTall) } label: {
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
                    HStack(spacing: 6) {
                        if let time {
                            Label {
                                Text(verbatim: DayPlanner.clock(time.arrival))
                            } icon: {
                                Image(systemName: time.reason == .pinned ? "pin.fill" : "clock")
                            }
                            .labelStyle(.titleAndIcon)
                            .font(Theme.font(11, .bold))
                            .monospacedDigit()
                            .foregroundStyle(time.reason == .pinned ? Theme.accent : Theme.ink)
                        }
                        Text(place.category.title)
                            .font(Theme.font(11, .bold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(place.category.color)
                    }
                    Text(place.name).font(Theme.font(16, .semibold)).lineLimit(2)
                    if !place.note.isEmpty {
                        Label(place.note, systemImage: "note.text")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let saved = store.savedDay(of: place, stop: stopID), saved != day {
                    // Gün sayısı azaldı: yer kendi günü geri gelince oraya döner.
                    Text("\(saved + 1). günden")
                        .font(Theme.font(11, .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.surface, in: Capsule())
                }
                if place.isEstimated { EstimatedTag() }
                // "…": basılı tutunca açılan menünün aynısı (Polarsteps gibi).
                Menu { menu(place, day: day) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Seçenekler"))
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
        Button { timing = place } label: {
            if let time = store.pinnedTime(of: place, stop: stopID) {
                Label("Saat: \(DayPlanner.clock(time))", systemImage: "clock")
            } else {
                Label("Saat belirle", systemImage: "clock")
            }
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

    /// Yerin penceresini açar. Listeden açılınca ayrıntı için daha yüksek
    /// (üstte harita kalır), haritadan açılınca yarım ekran.
    private func focus(_ place: Place, detent: PresentationDetent = .placeHalf) {
        if !showsAll, let day = store.dayIndex(of: place, stop: stopID) { selectedDay = day }
        sheetDetent = detent
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
        // `fewerDays`: gün sayısı 3'ten 2'ye inmiş; 3. günün yerleri "3. günden" etiketiyle 2. günde.
        if screen == "fewerDays" {
            // Gün sayısı RootView'da (açılışta) 2'ye indirildi.
            selectedDay = 1
            return
        }
        // `dayOrder`: 1. gün için Akıllı sıra önerisi (saatler ve nedenleri).
        if screen == "dayOrder" {
            ordering = OrderRequest(day: 0, mode: .smart)
            return
        }
        // `timed`: 1. günde yemek yerine saat verilmiş ve akıllı sıra uygulanmış (saatler listede).
        if screen == "timed" {
            // Saat ve akıllı sıra RootView'da (açılışta) verildi.
            panelStop = Self.panelStops.count - 1
            return
        }
        // `mapAdd`: haritada Google yerine dokunulmuş (Rotaya ekle, yer imi, yol tarifi).
        if screen == "mapAdd" {
            let shibuya = CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)
            guard let found = await GooglePlaces.shared.search("Ichiran Shibuya", near: shibuya).first else { return }
            sheetDetent = .placeHalf
            googlePlace = GooglePlaceRef(id: found.id, name: found.name, coordinate: found.coordinate)
            return
        }
        // `mapAdded`: aynı yer "Rotaya ekle" ile en yakın güne eklenmiş.
        if screen == "mapAdded" {
            let place = Place(name: "Ichiran Shibuya", city: city, latitude: 35.6614, longitude: 139.7010,
                              category: .food, source: .search)
            store.add(place)
            let day = store.planNearest(place, stop: stopID)
            selectedDay = day
            focus(place)
            return
        }
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

/// Şehir planının altında yana kayan "Popüler yerler" (Wikipedia'da en çok
/// okunan yakın yerler): fotoğraf, ad ve "+"; "+" yeri bu güne (Tüm
/// yerler'de rotası en yakın güne) ekler, rotadaysa ✓.
private struct PopularStrip: View {
    let city: String
    let stopID: UUID
    let day: Int?
    @EnvironmentObject private var store: AppStore
    @State private var places: [WikipediaService.PopularPlace] = []

    var body: some View {
        // Boşken de görünüm var olsun: içi boş `Group`a bağlı görev hiç çalışmaz.
        VStack(alignment: .leading, spacing: 10) {
            if !places.isEmpty {
                Text("Popüler yerler").font(Theme.font(19, .bold)).padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(places.prefix(15)) { item in card(item) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 1, alignment: .leading)
        .task(id: city) {
            guard let center = store.center(of: city) else { return }
            places = (try? await WikipediaService.shared.popularPlaces(latitude: center.latitude,
                                                                      longitude: center.longitude)) ?? []
        }
    }

    private func saved(_ item: WikipediaService.PopularPlace) -> Place? {
        let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        return store.savedPlace(named: item.name, near: coordinate) ?? store.savedPlace(named: item.title, near: coordinate)
    }

    private func card(_ item: WikipediaService.PopularPlace) -> some View {
        let category = PlaceCategory.guess(name: item.title) ?? .sight
        let existing = saved(item)
        let planned = existing.map { store.isPlanned($0, stop: stopID) } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            LocationPhoto(name: item.name, category: category, city: city,
                          latitude: item.latitude, longitude: item.longitude, englishTitle: item.title,
                          knownPhoto: item.thumbnailURL, size: 136, cornerRadius: 16)
                .overlay(alignment: .topTrailing) {
                    Button { add(item, category: category, existing: existing, planned: planned) } label: {
                        Image(systemName: planned ? "checkmark" : "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(planned ? .white : Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(planned ? Theme.ink : Color.white, in: Circle())
                            .softShadow()
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel(Text(planned ? LocalizedStringKey("Rotada") : LocalizedStringKey("Rotaya ekle")))
                }
            Text(item.name)
                .font(Theme.font(14, .semibold))
                .lineLimit(2)
                .frame(width: 136, alignment: .leading)
        }
    }

    private func add(_ item: WikipediaService.PopularPlace, category: PlaceCategory, existing: Place?, planned: Bool) {
        if let existing {
            if planned { store.removeFromPlan(existing, stop: stopID) } else { plan(existing) }
            return
        }
        let place = Place(name: item.name, city: city, latitude: item.latitude, longitude: item.longitude,
                          category: category, source: .search, wikipediaTitle: item.title)
        store.add(place)
        plan(place)
    }

    private func plan(_ place: Place) {
        if let day {
            store.plan(place, stop: stopID, day: day)
        } else {
            store.planNearest(place, stop: stopID)
        }
    }
}

/// Günün sırası penceresini açma isteği.
private struct OrderRequest: Identifiable {
    let id = UUID()
    var day: Int
    var mode: DayOrderSheet.Mode
    var message: String?
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

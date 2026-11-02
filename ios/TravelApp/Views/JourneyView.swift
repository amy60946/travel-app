import MapKit
import SwiftUI

/// Gezi planı (Polarsteps "Trip plan" gibi): üstte haritada numaralı
/// şehirler ve aralarında kesik çizgi; altta sırayla şehir kartları
/// (fotoğraf, "1-3. gün", gün sayısı − / +, konaklamalar), aralarında araba
/// süresi ya da uçuş. Kartın "Ekle" menüsü: yer, konaklama, uçuş, sonrasına
/// şehir. En altta "Şehir ekle". Karta dokununca şehrin günlük planı açılır.
struct JourneyView: View {
    let journeyID: UUID
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var mapFocus: MapFocus?
    @State private var sheet: JourneySheet?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    /// Geziden çıkarılacak şehir (planında yer varsa önce sorulur).
    @State private var removing: Destination?
    /// Yalnızca ekran görüntüsü için "Sil"i açık gösterilen şehir.
    @State private var revealedStop: UUID?
    /// Alttaki şehir listesinin paneli: küçük, yarım, büyük.
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 400
    /// Haritada dokunulan Google yeri (restoran, müze...): penceresi açık.
    @State private var googlePlace: GooglePlaceRef?
    @State private var googleDetent: PresentationDetent = .placeHalf
    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    var body: some View {
        Group {
            if let journey = store.journey(journeyID) {
                content(journey)
            } else {
                // Gezi silindi (ya da geri alındı): listeye dön.
                Color.white.onAppear { dismiss() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { sheetView($0) }
        .sheet(item: $googlePlace) { place in
            GooglePlaceSheet(place: place) { _ in googlePlace = nil }
                .placeSheetPresentation(detent: $googleDetent)
        }
        .alert("Gezinin adı", isPresented: $renaming) {
            TextField("Gezinin adı", text: $newName)
            Button("Kaydet") { store.renameJourney(journeyID, to: newName) }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Gezi silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Geziyi sil", role: .destructive) { store.deleteJourney(journeyID) }
        } message: {
            Text("Kayıtlı yerlerin silinmez.")
        }
        .confirmationDialog(removing.map { String(localized: "\($0.city) geziden çıkarılsın mı?") } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { stop in
            Button("Geziden çıkar", role: .destructive) { store.removeStop(stop.id, from: journeyID) }
        } message: { stop in
            Text("\(store.trip(stop: stop.id).placeIDs.count) yer bu gezinin planından çıkar; kayıtlarında ve koleksiyonlarında kalır. Şehri yeniden eklersen planı boş başlar.")
        }
        .task { await openLaunchScreen() }
    }

    private func content(_ journey: Journey) -> some View {
        let days = store.days(of: journey)
        let ranges = Journey.dayRanges(days: days)
        return ZStack(alignment: .bottom) {
            map(journey)
                .ignoresSafeArea()
                .overlay(alignment: .top) { header(journey) }
        }
        .slidingPanel(stops: [.height(110), .fraction(0.55), .belowTop(60)], selection: $panelStop,
                      isHidden: googlePlace != nil, onSettle: { panelHeight = $0 }) {
            Text(journey.stops.count == 1
                 ? String(localized: "\(days.reduce(0, +)) gün")
                 : String(localized: "\(journey.stops.count) şehir · \(days.reduce(0, +)) gün"))
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Polarsteps gibi: Gezi başlangıcı, şehirler (aralarında + ve
                // ulaşım), Gezi sonu.
                edgeRow(start: true, days: days.reduce(0, +))
                ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                    TransportConnector(from: index > 0 ? journey.stops[index - 1] : nil, to: stop,
                                       showsTransport: index > 0 || stop.arrivalMode != nil,
                                       onAddCity: { sheet = .addCity(after: index - 1) }) {
                        sheet = .transport(stop.id)
                    }
                    // Sola kaydırınca "Sil" (Oguz, 2026-11-02).
                    SwipeToDelete(reveals: revealedStop == stop.id) { remove(stop) } content: {
                        stopCard(stop, index: index, count: journey.stops.count,
                                 range: ranges[index], days: days[index])
                    }
                }
                addCityRow(after: journey.stops.count - 1)
                edgeRow(start: false, days: days.reduce(0, +))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .animation(.snappy, value: googlePlace)
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 16) }
        .animation(.snappy, value: store.undoMessage)
        .task(id: journey.stops.map(\.id)) {
            fitMap(journey)
            await fillCountries(journey)
        }
    }

    // MARK: - Harita

    /// Numaralı şehirler ve aralarında kesik çizgi.
    private func map(_ journey: Journey) -> some View {
        let markers = journey.stops.enumerated().map { index, stop in
            GoogleMap.Marker(id: stop.id.uuidString, coordinate: stop.coordinate, key: "\(index + 1)",
                             onTap: { path.append(.plan(stop.id)) }) {
                DayBadge(number: index + 1, size: 30).padding(8)
            }
        }
        let lines = journey.stops.count > 1
            ? [GoogleMap.Line(id: "journey", coordinates: journey.stops.map(\.coordinate), color: UIColor(Theme.ink),
                              width: 2.5, dashed: true, geodesic: true)]
            : []
        return GoogleMap(focus: $mapFocus, markers: markers, lines: lines,
                         padding: EdgeInsets(top: 52, leading: 0, bottom: panelHeight, trailing: 0),
                         onPlaceTap: { id, name, coordinate in
                             let name = name.replacingOccurrences(of: "\n", with: " ")
                             googleDetent = .placeHalf
                             googlePlace = GooglePlaceRef(id: id, name: name, coordinate: coordinate)
                         })
    }

    private func fitMap(_ journey: Journey) {
        let coordinates = journey.stops.map(\.coordinate)
        if coordinates.count == 1, let only = coordinates.first {
            mapFocus = .region(MKCoordinateRegion(center: only, latitudinalMeters: 60_000, longitudinalMeters: 60_000))
        } else if let region = MKCoordinateRegion(fitting: coordinates, padding: 1.6) {
            mapFocus = .region(region)
        }
    }

    private func header(_ journey: Journey) -> some View {
        HStack(alignment: .top) {
            CircleIconButton(systemImage: "chevron.left") { dismiss() }
                .accessibilityLabel(Text("Geri"))
            Spacer()
            Button {
                newName = journey.name
                renaming = true
            } label: {
                Text(journey.name)
                    .font(Theme.font(17, .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
                    .softShadow()
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button {
                    newName = journey.name
                    renaming = true
                } label: {
                    Label("Adını değiştir", systemImage: "pencil")
                }
                if Supabase.isConfigured {
                    Button { sheet = .share } label: {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Geziyi sil", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .softShadow()
            }
            .accessibilityLabel(Text("Gezi seçenekleri"))
        }
        .overlay(alignment: .topTrailing) {
            // Her haritadaki düğmeler, gezi menüsünün altında (liste tam
            // ekrandayken gizli).
            if !isFullScreen { MapControls(focus: $mapFocus).padding(.top, 50) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            if isFullScreen { Color.white.ignoresSafeArea(edges: .top) }
        }
        .animation(.snappy, value: isFullScreen)
    }

    /// Şehir listesi tam ekranda: üst çubuk beyaz zeminli.
    private var isFullScreen: Bool { panelStop == 2 && googlePlace == nil }

    // MARK: - Şehir kartı

    private func stopCard(_ stop: Destination, index: Int, count: Int,
                          range: ClosedRange<Int>, days: Int) -> some View {
        let planned = store.trip(stop: stop.id).placeIDs.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { path.append(.plan(stop.id)) } label: {
                    HStack(spacing: 14) {
                        CityPhoto(name: stop.city, englishTitle: stop.englishTitle,
                                  cover: store.cities.first { $0.name == stop.city }?.coverPlace)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topLeading) {
                                DayBadge(number: index + 1, size: 22).offset(x: -7, y: -7)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Journey.dayText(range))
                                .font(Theme.font(11, .bold))
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .foregroundStyle(Theme.muted)
                            HStack(spacing: 6) {
                                Text(stop.city).font(Theme.font(18, .bold)).lineLimit(1)
                                if let flag = stop.flag { Text(flag).font(.system(size: 15)) }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(planned == 0 ? String(localized: "Henüz yer yok") : String(localized: "\(planned) yer"))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                DayStepper(days: days) { store.setDays($0, stop: stop.id) }
            }

            ForEach(stop.stays) { stay in stayRow(stay, stop: stop) }

            addMenu(stop, index: index)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.hairline))
        .contextMenu {
            if index > 0 {
                Button { store.moveStop(stop.id, by: -1, in: journeyID) } label: {
                    Label("Öne al", systemImage: "arrow.up")
                }
            }
            if index < count - 1 {
                Button { store.moveStop(stop.id, by: 1, in: journeyID) } label: {
                    Label("Sona doğru taşı", systemImage: "arrow.down")
                }
            }
            Button(role: .destructive) { remove(stop) } label: {
                Label("Geziden çıkar", systemImage: "minus.circle")
            }
        }
    }

    /// Şehri geziden çıkarır; planında yer varsa önce sorar (Geri al da var).
    private func remove(_ stop: Destination) {
        if store.trip(stop: stop.id).placeIDs.isEmpty {
            store.removeStop(stop.id, from: journeyID)
        } else {
            removing = stop
        }
    }

    /// Polarsteps'teki "+" menüsü: yer, konaklama, uçuş, sonrasına şehir.
    private func addMenu(_ stop: Destination, index: Int) -> some View {
        Menu {
            Button { sheet = .addPlace(stop) } label: {
                Label("Yer ekle", systemImage: "mappin.and.ellipse")
            }
            Button { sheet = .stay(stop.id) } label: {
                Label("Konaklama ekle", systemImage: "bed.double")
            }
            Button { sheet = .transport(stop.id) } label: {
                Label(stop.arrivalMode == nil ? LocalizedStringKey("Geliş ulaşımı ekle")
                                              : LocalizedStringKey("Ulaşımı düzenle"),
                      systemImage: stop.arrivalMode?.symbol ?? "airplane")
            }
            Button { sheet = .addCity(after: index) } label: {
                Label("Sonrasına şehir ekle", systemImage: "plus.circle")
            }
        } label: {
            // Yalnızca "+" (Oguz, 2026-10-29).
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 36)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.hairline))
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Ekle"))
    }

    private func stayRow(_ stay: Stay, stop: Destination) -> some View {
        HStack(spacing: 10) {
            CategoryIcon(category: .hotel, size: 26)
            Text(stay.name).font(Theme.font(14, .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Menu {
                Picker("Gece", selection: Binding(get: { stay.nights }, set: { nights in
                    var changed = stay
                    changed.nights = nights
                    store.updateStay(changed, stop: stop.id, in: journeyID)
                })) {
                    ForEach(1...14, id: \.self) { Text("\($0) gece").tag($0) }
                }
                Button(role: .destructive) { store.removeStay(stay.id, stop: stop.id, in: journeyID) } label: {
                    Label("Kaldır", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(stay.nights) gece")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
            }
            .menuOrder(.fixed)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Son şehirden sonra: "+" ve "Şehir ekle" (sıradaki durak).
    private func addCityRow(after index: Int) -> some View {
        Button { sheet = .addCity(after: index) } label: {
            HStack(spacing: 12) {
                AddCircle()
                Text("Şehir ekle").font(Theme.font(15, .semibold))
                Spacer()
            }
            .padding(.leading, EdgeRow.lineInset - AddCircle.size / 2)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Şehir ekle"))
    }

    /// "Gezi başlangıcı" (ev) ve "Gezi sonu" (bayrak) satırları.
    private func edgeRow(start: Bool, days: Int) -> some View {
        EdgeRow(symbol: start ? "house.fill" : "flag.checkered",
                title: start ? String(localized: "Gezi başlangıcı") : String(localized: "Gezi sonu"),
                detail: start ? String(localized: "\(days) gün planlandı") : nil)
    }

    // MARK: - Pencereler

    @ViewBuilder
    private func sheetView(_ sheet: JourneySheet) -> some View {
        switch sheet {
        case .addCity(let index): NewTripView(mode: .add(journeyID: journeyID, index: index + 1))
        case .transport(let stopID): TransportSheet(journeyID: journeyID, stopID: stopID)
        case .stay(let stopID): StaySheet(journeyID: journeyID, stopID: stopID)
        case .addPlace(let stop): AddPlaceView(city: stop.city, stop: stop.id)
        case .share: ShareTripSheet(journeyID: journeyID)
        }
    }

    /// Eski gezilerin şehirlerinde ülke (bayrak) yok; konumdan bulunur.
    private func fillCountries(_ journey: Journey) async {
        for stop in journey.stops where stop.countryCode == nil {
            let location = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            if let code = try? await CLGeocoder().reverseGeocodeLocation(location).first?.isoCountryCode {
                store.setCountry(code, stop: stop.id, in: journeyID)
            }
        }
    }

    /// Yalnızca geliştirme sürümünde (ekran görüntüleri için): `-screen
    /// flight` uçuş, `stay` konaklama, `addCity` şehir ekleme penceresini açar.
    private func openLaunchScreen() async {
        #if DEBUG
        guard !Self.openedLaunchScreen, let journey = store.journey(journeyID) else { return }
        Self.openedLaunchScreen = true
        let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
        try? await Task.sleep(for: .seconds(1))
        switch screen {
        case "flight": if let stop = journey.stops.last { sheet = .transport(stop.id) }
        case "transport": if journey.stops.count > 1 { sheet = .transport(journey.stops[1].id) }
        case "swipeDelete": revealedStop = journey.stops.first?.id
        case "journeyFull": panelStop = 2
        case "stay": if let stop = journey.stops.first { sheet = .stay(stop.id) }
        case "addCity": sheet = .addCity(after: journey.stops.count - 1)
        case "shareTrip": sheet = .share
        default: break
        }
        #endif
    }
}

private enum JourneySheet: Identifiable {
    case addCity(after: Int)
    case transport(UUID)
    case stay(UUID)
    case addPlace(Destination)
    case share

    var id: String {
        switch self {
        case .addCity(let index): "city-\(index)"
        case .transport(let id): "transport-\(id)"
        case .stay(let id): "stay-\(id)"
        case .addPlace(let stop): "place-\(stop.id)"
        case .share: "share"
        }
    }
}

/// Gün sayısı: "− 3 gün +".
private struct DayStepper: View {
    let days: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            step("minus", enabled: days > 1, label: "Bir gün azalt") { onChange(days - 1) }
            Text("\(days) gün")
                .font(Theme.font(14, .semibold))
                .monospacedDigit()
                .frame(minWidth: 46)
            step("plus", enabled: days < 14, label: "Bir gün artır") { onChange(days + 1) }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
    }

    private func step(_ symbol: String, enabled: Bool, label: LocalizedStringKey,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
    }
}

/// İki şehir arası: kesik çizgi ve ulaşım çipi. Ulaşım seçilmediyse "+
/// Ulaşım ekle" (araba simgesi kendiliğinden görünmez); araçla gidiliyorsa
/// yol süresi ("446 km · 4 sa 43 dk"), uçak/tren/otobüste sefer ve saatler.
/// Dokununca ulaşım penceresi açılır.
private struct TransportConnector: View {
    let from: Destination?
    let to: Destination
    /// Ulaşım çipi görünsün mü (ilk şehirde yalnızca seçildiyse).
    var showsTransport = true
    /// "+": bu iki şehrin arasına şehir ekler.
    let onAddCity: () -> Void
    let onTap: () -> Void
    @State private var leg: TravelLegs.Leg?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAddCity) { AddCircle() }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Araya şehir ekle"))
                .padding(.leading, EdgeRow.lineInset - AddCircle.size / 2)
            if showsTransport { transportChip }
            Spacer()
        }
        .frame(height: 52)
        // Şehirleri birleştiren kesik çizgi; "+" onun üstünde.
        .background(alignment: .leading) {
            VerticalDash()
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                .frame(width: 2)
                .padding(.leading, EdgeRow.lineInset - 1)
        }
        .task(id: "\(from?.id.uuidString ?? "")>\(to.id)>\(to.arrivalMode?.rawValue ?? "")") {
            guard let from, to.arrivalMode == .car else { return }
            leg = await TravelLegs.leg(from: from.coordinate, to: to.coordinate)
        }
    }

    private var transportChip: some View {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: to.arrivalMode?.symbol ?? "point.topleft.down.to.point.bottomright.curvepath")
                    Text(text)
                }
                .font(Theme.font(13, .semibold))
                .foregroundStyle(to.arrivalMode == nil ? .white : Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(to.arrivalMode == nil ? Theme.ink : Theme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
    }

    private var text: String {
        guard let mode = to.arrivalMode else { return String(localized: "Ulaşım ekle") }
        if mode == .car {
            guard let leg else { return mode.title }
            return leg.seconds == nil ? String(localized: "Araçla yol bulunamadı") : TravelLegs.text(leg)
        }
        let summary = to.flight?.summary ?? ""
        return summary.isEmpty ? mode.title : summary
    }
}

/// Küçük yuvarlak "+" (şehirlerin arasında ve sonunda).
private struct AddCircle: View {
    static let size: CGFloat = 30

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: Self.size, height: Self.size)
            .background(.white, in: Circle())
            .overlay(Circle().stroke(Theme.hairline))
    }
}

/// "Gezi başlangıcı" ve "Gezi sonu": siyah yuvarlak simge, başlık, ayrıntı.
private struct EdgeRow: View {
    /// Şehir fotoğraflarının ortası: simgeler ve "+" bu çizgiye oturur
    /// (kartın iç boşluğu 14 + fotoğrafın yarısı 32).
    static let lineInset: CGFloat = 46

    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.ink, in: Circle())
            Text(title).font(Theme.font(15, .bold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.surface, in: Capsule())
            }
        }
        .padding(.leading, lineInsetPadding)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var lineInsetPadding: CGFloat { Self.lineInset - 18 }
}

private struct VerticalDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Sola kaydırınca sağda kırmızı "Sil" düğmesi çıkar (iOS listelerindeki
/// gibi); sağa kaydırınca ya da başka yere dokununca kapanır.
private struct SwipeToDelete<Content: View>: View {
    /// Yalnızca ekran görüntüsü için düğmeyi açık gösterir.
    var reveals = false
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private static var buttonWidth: CGFloat { 88 }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                close()
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 17, weight: .semibold))
                    Text("Sil").font(Theme.font(13, .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: Self.buttonWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            .buttonStyle(.plain)
            .opacity(offset < -4 ? 1 : 0)
            .accessibilityHidden(true)

            content()
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            // Yalnızca yatay kaydırma; aşağı-yukarı liste kayar.
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                            let base = isOpen ? -(Self.buttonWidth + 8) : 0
                            offset = min(0, max(-(Self.buttonWidth + 60), base + value.translation.width))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else {
                                withAnimation(.snappy) { offset = isOpen ? -(Self.buttonWidth + 8) : 0 }
                                return
                            }
                            withAnimation(.snappy) {
                                isOpen = offset < -Self.buttonWidth / 2
                                offset = isOpen ? -(Self.buttonWidth + 8) : 0
                            }
                        })
                .accessibilityAction(named: Text("Sil")) { onDelete() }
        }
        .onChange(of: reveals, initial: true) { _, reveals in
            guard reveals else { return }
            withAnimation(.snappy) {
                isOpen = true
                offset = -(Self.buttonWidth + 8)
            }
        }
    }

    private func close() {
        withAnimation(.snappy) {
            isOpen = false
            offset = 0
        }
    }
}

// MARK: - Ulaşım

/// Şehre nasıl gelinir: Araç / Uçak / Tren / Otobüs. Araçta yol süresi
/// kendiliğinden hesaplanır; uçak, tren ve otobüste nereden, uçuş ya da
/// sefer numarası, kalkış ve varış saati, not. Yalnızca plana not; bilet,
/// tarih ya da rezervasyon yok.
struct TransportSheet: View {
    let journeyID: UUID
    let stopID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TravelMode = .car
    @State private var details = Flight()
    @State private var leg: TravelLegs.Leg?
    @State private var loaded = false

    private var stops: [Destination] { store.journey(journeyID)?.stops ?? [] }
    private var stop: Destination? { stops.first { $0.id == stopID } }
    private var previous: Destination? {
        guard let index = stops.firstIndex(where: { $0.id == stopID }), index > 0 else { return nil }
        return stops[index - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Ulaşım") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let stop {
                        Text(verbatim: "\(fromText) → \(stop.city)")
                            .font(Theme.font(22, .bold))
                            .lineLimit(2)
                    }
                    modePicker
                    if mode == .car {
                        carInfo
                    } else {
                        if previous == nil { field("Nereden", text: $details.from, prompt: "İstanbul") }
                        field(mode == .flight ? "Uçuş numarası" : "Sefer numarası", text: $details.number,
                              prompt: mode == .flight ? "TK 52" : "")
                        HStack(spacing: 12) {
                            TimeField(title: "Kalkış", text: $details.departure)
                            TimeField(title: "Varış", text: Binding(get: { details.arrival ?? "" },
                                                                   set: { details.arrival = $0 }))
                        }
                    }
                    field("Not", text: $details.note, prompt: mode == .car ? "Mola, yakıt…" : "Terminal, peron, bagaj…")
                    WideButton(title: String(localized: "Kaydet")) {
                        store.setTransport(mode, details: details, stop: stopID, in: journeyID)
                        dismiss()
                    }
                    .padding(.top, 4)
                    if stop?.arrivalMode != nil {
                        Button(role: .destructive) {
                            store.setTransport(nil, details: nil, stop: stopID, in: journeyID)
                            dismiss()
                        } label: {
                            Text("Ulaşımı kaldır").font(Theme.font(15, .semibold)).frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            mode = stop?.arrivalMode ?? .car
            details = stop?.flight ?? Flight(from: previous?.city ?? "")
        }
        .task(id: mode) {
            guard mode == .car, let previous, let stop else { return }
            leg = await TravelLegs.leg(from: previous.coordinate, to: stop.coordinate)
        }
    }

    private var fromText: String {
        if let previous { return previous.city }
        let typed = details.from.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? "…" : typed
    }

    /// Dört büyük düğme; seçili olan siyah.
    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(TravelMode.allCases) { option in
                Button { withAnimation(.snappy) { mode = option } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 20, weight: .semibold))
                        Text(option.title).font(Theme.font(13, .semibold))
                    }
                    .foregroundStyle(mode == option ? .white : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(mode == option ? Theme.ink : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var carInfo: some View {
        if previous == nil {
            Text("Gezinin ilk şehri: araçla geliyorsan not ekleyebilirsin.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "car.fill").foregroundStyle(Theme.muted)
                if let leg {
                    Text(leg.seconds == nil ? String(localized: "Araçla yol bulunamadı") : TravelLegs.text(leg))
                        .font(Theme.font(16, .semibold))
                } else {
                    ProgressView()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            TextField(prompt, text: text)
                .font(Theme.font(16))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.hairline, lineWidth: 1.5))
        }
    }
}

/// Saat seçimi ("10:30"): boşsa "Saat ekle" düğmesi, doluysa saat tekeri.
private struct TimeField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var date: Binding<Date> {
        Binding(get: { Self.formatter.date(from: text) ?? Self.formatter.date(from: "10:00")! },
                set: { text = Self.formatter.string(from: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            HStack {
                if text.isEmpty {
                    Button { text = "10:00" } label: {
                        Label("Saat ekle", systemImage: "clock").font(Theme.font(15, .semibold))
                    }
                    .buttonStyle(.plain)
                } else {
                    DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.hairline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Saati sil"))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.hairline, lineWidth: 1.5))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Konaklama

/// Konaklama ekle: şehirdeki oteller (Apple Haritalar, ücretsiz) ya da
/// yazılan ad. Gece sayısı sonra karttan değişir. Rezervasyon yok.
struct StaySheet: View {
    let journeyID: UUID
    let stopID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    private var stop: Destination? { store.journey(journeyID)?.stops.first { $0.id == stopID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Konaklama ekle") { dismiss() }
            SearchField(text: $query, prompt: "Otel, pansiyon ya da ev ara", isSearching: searching)
                .padding(.horizontal, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let typed = query.trimmingCharacters(in: .whitespaces)
                    if !typed.isEmpty {
                        Button { add(name: typed, coordinate: nil) } label: {
                            ResultRow(title: String(localized: "“\(typed)” olarak ekle"),
                                      subtitle: String(localized: "Konumsuz, yalnızca adıyla")) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 18))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Theme.surface)
                            } trailing: {
                                Image(systemName: "plus")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    SectionTitle(typed.isEmpty ? "Şehirdeki oteller" : "Sonuçlar")
                    if !searching && results.isEmpty {
                        Text("Sonuç bulunamadı.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    ForEach(results, id: \.self) { item in
                        Button { add(name: item.name ?? typed, coordinate: item.placemark.coordinate) } label: {
                            ResultRow(title: item.name ?? "", subtitle: item.placemark.title ?? "") {
                                CategoryTile(category: .hotel)
                            } trailing: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1.5))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        guard let stop else { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text.isEmpty ? "hotel" : text
        request.resultTypes = .pointOfInterest
        if text.isEmpty { request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel]) }
        let center = store.center(of: stop.city) ?? stop.coordinate
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 15_000, longitudinalMeters: 15_000)
        let found = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        searching = false
        if query.trimmingCharacters(in: .whitespaces) == text { results = found }
    }

    private func add(name: String, coordinate: CLLocationCoordinate2D?) {
        guard let stop, !name.isEmpty else { return }
        let nights = max(store.trip(stop: stopID).days - 1, 1)
        store.addStay(Stay(name: name, latitude: coordinate?.latitude, longitude: coordinate?.longitude, nights: nights),
                      stop: stopID, in: journeyID)
        dismiss()
    }
}

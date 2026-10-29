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

    @State private var position: MapCameraPosition = .automatic
    @State private var sheet: JourneySheet?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    /// Alttaki şehir listesinin paneli: küçük, yarım, büyük.
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 400
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
        .task { await openLaunchScreen() }
    }

    private func content(_ journey: Journey) -> some View {
        let days = store.days(of: journey)
        let ranges = Journey.dayRanges(days: days)
        return ZStack(alignment: .bottom) {
            map(journey)
                .safeAreaPadding(.bottom, panelHeight + 30)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { header(journey) }

            DraggablePanel(stops: [.height(140), .fraction(0.55), .fraction(0.9)], selection: $panelStop,
                           onSettle: { panelHeight = $0 }) {
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
                    ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                        if index > 0 || stop.flight != nil {
                            TransportConnector(from: index > 0 ? journey.stops[index - 1] : nil, to: stop) {
                                sheet = .flight(stop.id)
                            }
                        }
                        stopCard(stop, index: index, count: journey.stops.count,
                                 range: ranges[index], days: days[index])
                    }

                    addCityRow(after: journey.stops.count - 1)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 16) }
        .animation(.snappy, value: store.undoMessage)
        .task(id: journey.stops.map(\.id)) {
            fitMap(journey)
            await fillCountries(journey)
        }
    }

    // MARK: - Harita

    private func map(_ journey: Journey) -> some View {
        Map(position: $position) {
            ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.city, coordinate: stop.coordinate, anchor: .center) {
                    Button { path.append(.city(stop.city)) } label: {
                        DayBadge(number: index + 1, size: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            if journey.stops.count > 1 {
                MapPolyline(coordinates: journey.stops.map(\.coordinate), contourStyle: .geodesic)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaPadding(.top, 52)
    }

    private func fitMap(_ journey: Journey) {
        let coordinates = journey.stops.map(\.coordinate)
        if coordinates.count == 1, let only = coordinates.first {
            position = .region(MKCoordinateRegion(center: only, latitudinalMeters: 60_000, longitudinalMeters: 60_000))
        } else if let region = MKCoordinateRegion(fitting: coordinates, padding: 1.6) {
            position = .region(region)
        }
    }

    private func header(_ journey: Journey) -> some View {
        HStack {
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Şehir kartı

    private func stopCard(_ stop: Destination, index: Int, count: Int,
                          range: ClosedRange<Int>, days: Int) -> some View {
        let planned = store.trip(for: stop.city).placeIDs.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { path.append(.city(stop.city)) } label: {
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
                                .foregroundStyle(Theme.accent)
                            HStack(spacing: 6) {
                                Text(stop.city).font(Theme.font(18, .bold)).lineLimit(1)
                                if let flag = stop.flag { Text(flag).font(.system(size: 15)) }
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
                DayStepper(days: days) { store.setDays($0, city: stop.city) }
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
            Button(role: .destructive) { store.removeStop(stop.id, from: journeyID) } label: {
                Label("Geziden çıkar", systemImage: "minus.circle")
            }
        }
    }

    /// Polarsteps'teki "+" menüsü: yer, konaklama, uçuş, sonrasına şehir.
    private func addMenu(_ stop: Destination, index: Int) -> some View {
        Menu {
            Button { sheet = .addPlace(stop.city) } label: {
                Label("Yer ekle", systemImage: "mappin.and.ellipse")
            }
            Button { sheet = .stay(stop.id) } label: {
                Label("Konaklama ekle", systemImage: "bed.double")
            }
            Button { sheet = .flight(stop.id) } label: {
                Label(stop.flight == nil ? LocalizedStringKey("Geliş uçuşu ekle") : LocalizedStringKey("Uçuşu düzenle"),
                      systemImage: "airplane")
            }
            Button { sheet = .addCity(after: index) } label: {
                Label("Sonrasına şehir ekle", systemImage: "plus.circle")
            }
        } label: {
            SecondaryLabel(title: "Ekle", systemImage: "plus", showsChevron: true)
        }
        .menuOrder(.fixed)
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

    private func addCityRow(after index: Int) -> some View {
        Button { sheet = .addCity(after: index) } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Şehir ekle").font(Theme.font(17, .bold))
                    Text("Sıradaki durağın neresi?").font(Theme.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pencereler

    @ViewBuilder
    private func sheetView(_ sheet: JourneySheet) -> some View {
        switch sheet {
        case .addCity(let index): NewTripView(mode: .add(journeyID: journeyID, index: index + 1))
        case .flight(let stopID): FlightSheet(journeyID: journeyID, stopID: stopID)
        case .stay(let stopID): StaySheet(journeyID: journeyID, stopID: stopID)
        case .addPlace(let city): AddPlaceView(city: city)
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
        case "flight": if let stop = journey.stops.last { sheet = .flight(stop.id) }
        case "stay": if let stop = journey.stops.first { sheet = .stay(stop.id) }
        case "addCity": sheet = .addCity(after: journey.stops.count - 1)
        default: break
        }
        #endif
    }
}

private enum JourneySheet: Identifiable {
    case addCity(after: Int)
    case flight(UUID)
    case stay(UUID)
    case addPlace(String)

    var id: String {
        switch self {
        case .addCity(let index): "city-\(index)"
        case .flight(let id): "flight-\(id)"
        case .stay(let id): "stay-\(id)"
        case .addPlace(let city): "place-\(city)"
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

/// İki şehir arası: kesik çizgi ve araba süresi ("446 km · 4 sa 43 dk") ya
/// da uçuş ("TK 52 · 10:30"). Yol yoksa "Uçuş ekle". Dokununca uçuş penceresi.
private struct TransportConnector: View {
    let from: Destination?
    let to: Destination
    let onTap: () -> Void
    @State private var leg: TravelLegs.Leg?

    var body: some View {
        HStack(spacing: 14) {
            VerticalDash()
                .stroke(Theme.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                .frame(width: 2, height: 46)
                .padding(.leading, 45)
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                    Text(text)
                }
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .task(id: "\(from?.id.uuidString ?? "")>\(to.id)") {
            guard let from, to.flight == nil else { return }
            leg = await TravelLegs.leg(from: from.coordinate, to: to.coordinate)
        }
    }

    private var symbol: String {
        if to.flight != nil { return "airplane" }
        if let leg, leg.seconds == nil { return "airplane" }
        return "car.fill"
    }

    private var text: String {
        if let flight = to.flight {
            return flight.from.isEmpty ? flight.summary : "\(flight.from) → \(flight.summary)"
        }
        guard let leg else { return "…" }
        if leg.seconds == nil {
            return String(localized: "Uçuş ekle · \(Int((leg.meters / 1000).rounded())) km")
        }
        return TravelLegs.text(leg)
    }
}

private struct VerticalDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Uçuş

/// Şehre uçuş: nereden, uçuş numarası, kalkış saati, not. Bilet ya da tarih yok.
struct FlightSheet: View {
    let journeyID: UUID
    let stopID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var flight = Flight()
    @State private var loaded = false

    private var stops: [Destination] { store.journey(journeyID)?.stops ?? [] }
    private var stop: Destination? { stops.first { $0.id == stopID } }
    private var previous: Destination? {
        guard let index = stops.firstIndex(where: { $0.id == stopID }), index > 0 else { return nil }
        return stops[index - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Uçuş") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let stop {
                        HStack(spacing: 8) {
                            Image(systemName: "airplane")
                            Text(verbatim: "\(flight.from.isEmpty ? "…" : flight.from) → \(stop.city)")
                        }
                        .font(Theme.font(20, .bold))
                    }
                    field("Nereden", text: $flight.from, prompt: "İstanbul")
                    field("Uçuş numarası", text: $flight.number, prompt: "TK 52")
                    field("Kalkış saati", text: $flight.departure, prompt: "10:30")
                    field("Not", text: $flight.note, prompt: "Terminal, bagaj…")
                    WideButton(title: String(localized: "Kaydet")) {
                        store.setFlight(flight, stop: stopID, in: journeyID)
                        dismiss()
                    }
                    .padding(.top, 6)
                    if stop?.flight != nil {
                        Button(role: .destructive) {
                            store.setFlight(nil, stop: stopID, in: journeyID)
                            dismiss()
                        } label: {
                            Text("Uçuşu sil").font(Theme.font(15, .semibold)).frame(maxWidth: .infinity)
                        }
                    }
                    Text("Uçuş yalnızca plana not olarak eklenir; bilet satın alma yok.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            flight = stop?.flight ?? Flight(from: previous?.city ?? "")
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
                    Text("Arama: Apple Haritalar · Rezervasyon yok, yalnızca plana not.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 12)
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
        let nights = max(store.trip(for: stop.city).days - 1, 1)
        store.addStay(Stay(name: name, latitude: coordinate?.latitude, longitude: coordinate?.longitude, nights: nights),
                      stop: stopID, in: journeyID)
        dismiss()
    }
}

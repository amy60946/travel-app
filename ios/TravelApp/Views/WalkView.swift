import MapKit
import SwiftUI

/// Yürü: harita navigasyon açısında (yürüdüğün yöne dönük, eğik); rota
/// senin konumundan başlar (sana en yakın duraktan girer, kalanları en kısa
/// yolla dizer; elle sıralanan günde senin sıran). Altta tek kart: durak
/// (fotoğraf, tür, ad, mesafe; sağa-sola kaydırınca önceki/sonraki durak)
/// ve anlatım (yazının tamamı bölüm bölüm: çiplerle bölüme atla, basılı
/// tutunca bölümü atla; 10 sn geri/ileri, hız, önceki/sonraki durak).
/// Durağa 50 m yaklaşınca anlatım kendiliğinden başlar.
struct WalkView: View {
    /// Gezideki şehir (`Destination.id`).
    let stopID: UUID
    let dayIndex: Int
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var narrator = Narrator.shared
    @StateObject private var tracker = LocationTracker()
    @Environment(\.dismiss) private var dismiss

    @State private var mapFocus: MapFocus?
    /// Harita konumu yürüme yönüne dönük, eğik izliyor mu? Haritayı
    /// kaydırınca ya da başka durağa bakınca durur; düğmeyle döner.
    @State private var following = true
    /// Yürüyüş sırası (konuma göre dizildiyse); boşsa günün sırası.
    @State private var order: [UUID] = []
    @State private var orderedFromLocation = false
    /// Konum ilk geldiğinde sıra bir kez kuruldu.
    @State private var checkedOrder = false
    /// Durak kendiliğinden değişti (varış, sıra): harita izlemeyi bırakmaz.
    @State private var changesQuietly = false
    /// Karttaki durak.
    @State private var current = 0
    @State private var narrated: Set<UUID> = []
    /// Anlatımı hazırlanan durak (Wikipedia'dan geliyor).
    @State private var preparing: UUID?
    @State private var narration: Task<Void, Never>?
    @State private var route: WalkingRoutes.DayRoute?
    @State private var banner: String?
    @State private var guidance: GuidanceDestination?
    @State private var cardHeight: CGFloat = 220

    /// Anlatımın başlama mesafesi (Tokyo testinde ayarlanacak).
    private let triggerMeters: CLLocationDistance = 50

    private var dayPlaces: [Place] {
        let days = store.dayPlan(stop: stopID)
        return days.indices.contains(dayIndex) ? days[dayIndex] : []
    }

    /// Yürüyüşün durakları, yürüme sırasıyla.
    private var stops: [Place] {
        let places = dayPlaces
        guard !order.isEmpty else { return places }
        let ordered = order.compactMap { id in places.first { $0.id == id } }
        return ordered + places.filter { !order.contains($0.id) }
    }

    private var currentStop: Place? {
        let stops = self.stops
        return stops.indices.contains(current) ? stops[current] : nil
    }

    var body: some View {
        let stops = self.stops
        ZStack(alignment: .bottom) {
            GoogleMap(focus: $mapFocus, markers: markers(stops), lines: lines, showsGooglePlaces: false,
                      padding: EdgeInsets(top: 110, leading: 0, bottom: cardHeight - 20, trailing: 0),
                      onUserGesture: { following = false })
                .ignoresSafeArea()
            VStack(spacing: 10) {
                topBar(stops)
                if let banner {
                    Text(banner)
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.ink, in: Capsule())
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            card(stops)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            tracker.start()
            mapFocus = .fitting(stops.map(\.coordinate), animated: false)
        }
        .onDisappear {
            tracker.stop()
            narration?.cancel()
        }
        .onReceive(tracker.$location) { location in
            guard let location else { return }
            if !checkedOrder { orderFromLocation(location) }
            if following { mapFocus = MapFocus(target: .follow(location, zoom: 17)) }
            checkArrival(at: location)
        }
        .onChange(of: current) { _, index in
            // Kullanıcı başka durağa bakınca harita o durağa gider (izleme durur).
            if changesQuietly {
                changesQuietly = false
                return
            }
            let stops = self.stops
            guard stops.indices.contains(index) else { return }
            following = false
            mapFocus = .point(stops[index].coordinate, zoom: 16)
        }
        .task(id: stops.map(\.id)) { route = await WalkingRoutes.route(through: stops) }
        .task(id: stops.map(\.id)) { await prefetchArticles(stops) }
        .task { await openLaunchScreen() }
        .fullScreenCover(item: $guidance) { GuidanceView(destination: $0) }
        .animation(.snappy, value: banner)
        .animation(.snappy, value: narrator.isActive)
    }

    // MARK: - Harita

    private func markers(_ stops: [Place]) -> [GoogleMap.Marker] {
        stops.enumerated().map { index, place in
            GoogleMap.Marker.place(place, size: index == current ? 40 : 30, day: index,
                                   showsTitle: index == current, zIndex: index == current ? 1 : 0) {
                current = index
            }
        }
    }

    private var lines: [GoogleMap.Line] {
        (route?.lines ?? []).enumerated().map { index, line in
            GoogleMap.Line(id: "route-\(index)", coordinates: line, color: UIColor(Theme.accent).withAlphaComponent(0.6))
        }
    }

    /// Kapat, "1. gün · 6 durak" ve harita açısı (navigasyon ↔ yukarıdan).
    private func topBar(_ stops: [Place]) -> some View {
        HStack {
            CircleIconButton(systemImage: "xmark") {
                narrator.stop()
                dismiss()
            }
            .accessibilityLabel(Text("Kapat"))
            Spacer()
            VStack(spacing: 1) {
                Text("\(dayIndex + 1). gün · \(stops.count) durak").font(Theme.font(15, .bold))
                if orderedFromLocation {
                    Text("Sana en yakın duraktan").font(Theme.font(11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.white, in: Capsule())
            .softShadow()
            Spacer()
            CircleIconButton(systemImage: following ? "map" : "location.north.line.fill") { toggleCamera(stops) }
                .accessibilityLabel(Text(following ? LocalizedStringKey("Yukarıdan gör") : LocalizedStringKey("Konumumu izle")))
        }
    }

    private func toggleCamera(_ stops: [Place]) {
        if following {
            following = false
            var points = stops.map(\.coordinate)
            if let location = tracker.location { points.append(location.coordinate) }
            mapFocus = .fitting(points)
        } else {
            following = true
            if let location = tracker.location {
                mapFocus = MapFocus(target: .follow(location, zoom: 17))
            } else {
                mapFocus = .user(zoom: 17)
            }
        }
    }

    // MARK: - Alttaki kart

    private func card(_ stops: [Place]) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.hairline).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 4)
            if stops.isEmpty {
                Text("Bu gün boş").font(Theme.headline).padding(.vertical, 30)
            } else {
                TabView(selection: $current) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                        stopCard(place, index: index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 92)
                pageDots(count: stops.count)
                Divider().padding(.top, 10)
                player(stops)
            }
        }
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius, topTrailingRadius: Theme.sheetRadius)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Durak: fotoğraf (köşesinde tür simgesi ve sıra), tür, ad, mesafe; yol tarifi.
    private func stopCard(_ place: Place, index: Int) -> some View {
        HStack(spacing: 14) {
            PlaceRowThumbnail(place: place, size: 72)
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(Theme.font(11, .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Theme.ink, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: -6, y: -6)
                }
            VStack(alignment: .leading, spacing: 3) {
                Label(place.category.title, systemImage: place.category.symbol)
                    .font(Theme.font(11, .bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(place.category.color)
                Text(place.name).font(Theme.font(18, .bold)).lineLimit(2)
                Text(distanceText(to: place)).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            DirectionsButton { guidance = GuidanceDestination(place: place) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .contentShape(Rectangle())
    }

    private func distanceText(to place: Place) -> String {
        guard let location = tracker.location else {
            return String(localized: "Gezme süresi \(DayPlanner.durationText(place.visitDuration))")
        }
        let meters = location.distance(from: place.location)
        let distance = Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        let minutes = Int((meters * 1.3 / 80).rounded())
        return meters < triggerMeters ? String(localized: "Buradasın")
                                      : String(localized: "\(distance) · yürüyerek \(max(minutes, 1)) dk")
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 5) {
            if count <= 14 {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(index == current ? Theme.ink : Theme.hairline)
                        .frame(width: 6, height: 6)
                }
            } else {
                Text(verbatim: "\(current + 1)/\(count)").font(Theme.font(12, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }

    /// Anlatım: çalarken bölüm çipleri, çizgi ve düğmeler; çalmıyorsa
    /// "Dinle" ve yaklaşınca başlayacağı bilgisi.
    @ViewBuilder
    private func player(_ stops: [Place]) -> some View {
        let place = currentStop
        if narrator.isActive {
            VStack(spacing: 8) {
                if let title = narrator.currentTitle, title != place?.name {
                    Text("Şu an: \(title)")
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }
                NarrationChapters()
                    .padding(.horizontal, 6)
                NarrationTimeline().padding(.horizontal, 20)
                controls(stops)
            }
            .padding(.top, 10)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    stepButton("backward.end.fill", label: "Önceki durak", disabled: current == 0) { step(-1, stops) }
                    Spacer()
                    Button { if let place { narrate(place) } } label: {
                        HStack(spacing: 8) {
                            if preparing != nil {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Dinle")
                        }
                        .font(Theme.font(16, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(height: 48)
                        .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(place == nil || preparing != nil)
                    Spacer()
                    stepButton("forward.end.fill", label: "Sonraki durak", disabled: current >= stops.count - 1) { step(1, stops) }
                }
                .padding(.horizontal, 20)
                Text("Durağa yaklaşınca anlatım kendiliğinden başlar")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 12)
        }
    }

    /// Önceki durak, 10 sn geri, oynat/duraklat, 10 sn ileri, sonraki durak, hız.
    private func controls(_ stops: [Place]) -> some View {
        HStack(spacing: 0) {
            stepButton("backward.end.fill", label: "Önceki durak", disabled: current == 0) { step(-1, stops) }
            Spacer()
            NarrationControls()
            Spacer()
            stepButton("forward.end.fill", label: "Sonraki durak", disabled: current >= stops.count - 1) { step(1, stops) }
            Spacer()
            NarrationSpeedButton()
        }
        .padding(.horizontal, 20)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(Text(label))
    }

    /// Önceki/sonraki durağa geçer; anlatım çalıyorsa o durağın anlatımı baştan başlar.
    private func step(_ offset: Int, _ stops: [Place]) {
        let target = current + offset
        guard stops.indices.contains(target) else { return }
        let wasPlaying = narrator.isActive
        withAnimation(.snappy) { current = target }
        if wasPlaying { narrate(stops[target]) }
    }

    // MARK: - Sıra, varış ve anlatım

    /// Konum ilk bulununca: elle sıralanmayan günde sana en yakın duraktan
    /// başlayıp en kısa yolla dizilir.
    private func orderFromLocation(_ location: CLLocation) {
        checkedOrder = true
        let places = dayPlaces
        guard places.count > 1, !store.isManuallyOrdered(day: dayIndex, stop: stopID) else { return }
        let start = RoutePlanner.Point(id: UUID(), latitude: location.coordinate.latitude,
                                       longitude: location.coordinate.longitude)
        order = RoutePlanner.nearestNeighborOrder(places.map(\.point), from: start).map(\.id)
        orderedFromLocation = true
        if current != 0 { changesQuietly = true }
        current = 0
        show(String(localized: "Rota sana en yakın duraktan başlıyor"))
    }

    private func checkArrival(at location: CLLocation) {
        let stops = self.stops
        let near = stops.enumerated()
            .filter { !narrated.contains($0.element.id) && location.distance(from: $0.element.location) <= triggerMeters }
            .min { location.distance(from: $0.element.location) < location.distance(from: $1.element.location) }
        guard let near else { return }
        narrated.insert(near.element.id)
        if current != near.offset { changesQuietly = true }
        withAnimation(.snappy) { current = near.offset }
        show(String(localized: "\(near.element.name): anlatım başladı"))
        narrate(near.element)
    }

    private func show(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            if banner == message { banner = nil }
        }
    }

    /// Önce özet okunur; yazının tamamı gelince bölümler eklenir (özetten
    /// sonra okunur, çiplerle atlanır).
    private func narrate(_ place: Place) {
        narration?.cancel()
        narrated.insert(place.id)
        narration = Task {
            let fallback = String(localized: "\(place.name). \(place.category.title).")
            guard let title = place.wikipediaTitle else {
                narrator.speak(fallback, title: place.name, language: WikipediaService.narrationLanguage)
                return
            }
            preparing = place.id
            let summary = await WikipediaService.shared.summary(englishTitle: title)
            preparing = nil
            guard !Task.isCancelled else { return }
            guard let summary else {
                narrator.speak(fallback, title: place.name, language: WikipediaService.narrationLanguage)
                return
            }
            narrator.speak(summary: summary, article: nil, title: place.name)
            guard let article = await WikipediaService.shared.article(englishTitle: title),
                  !Task.isCancelled, article.language == summary.language else { return }
            narrator.append(sections: article.sections.map { (heading: $0.heading, text: $0.text) }, to: place.name)
        }
    }

    /// Yürüyüşte beklememek için günün yazıları (ve çevirileri) önceden
    /// hazırlanır; telefonda saklanır, internetsiz de okunur.
    private func prefetchArticles(_ stops: [Place]) async {
        for place in stops {
            guard !Task.isCancelled else { return }
            if let title = place.wikipediaTitle {
                _ = await WikipediaService.shared.summary(englishTitle: title)
                _ = await WikipediaService.shared.article(englishTitle: title)
            }
        }
    }

    /// Yalnızca geliştirme sürümünde (ekran görüntüleri için): `walkPlaying`
    /// ikinci durağın anlatımını bölümleriyle çalarken (duraklatılmış) gösterir.
    private func openLaunchScreen() async {
        #if DEBUG
        try? await Task.sleep(for: .seconds(1))
        guard UserDefaults.standard.string(forKey: "screen") == "walkPlaying", stops.count > 1 else { return }
        current = 1
        let place = stops[1]
        narrator.speak(sections: [
            (heading: String(localized: "Hakkında"), text: "\(place.name), Tokyo'nun en çok ziyaret edilen yerlerinden biridir. "
                + "Her mevsim farklı bir yüzü vardır ve sabah erken saatlerde daha sakindir."),
            (heading: "Tarihçe", text: "Yapı 1920 yılında tamamlandı, savaşta zarar gördü ve 1958'de yeniden inşa edildi. "
                + "Bugünkü hâli o yıllardaki çizimlere sadık kalınarak yapıldı."),
            (heading: "Mimari", text: "Geleneksel Japon mimarisinin sade çizgileri burada açıkça görülür."),
            (heading: "Bugün", text: "Her yıl milyonlarca kişi burayı ziyaret eder; bayramlarda kalabalık olur."),
        ], title: place.name, language: "tr")
        try? await Task.sleep(for: .seconds(2))
        narrator.togglePause()
        #endif
    }
}

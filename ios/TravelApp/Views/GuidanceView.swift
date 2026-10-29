import AVFoundation
import MapKit
import NaturalLanguage
import SwiftUI

/// Uygulama içi yol tarifinin hedefi: kayıtlı yer ya da haritada dokunulan yer.
struct GuidanceDestination: Identifiable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
    var category: PlaceCategory
    var placeID: UUID?

    var id: String { "\(latitude),\(longitude)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    init(place: Place) {
        name = place.name
        latitude = place.latitude
        longitude = place.longitude
        category = place.category
        placeID = place.id
    }

    init(item: MKMapItem, category: PlaceCategory) {
        name = item.name ?? String(localized: "Yer")
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
        self.category = category
    }
}

/// Yürüyüş yol tarifi uygulamanın içinde (araba GPS'i gibi): harita
/// konumunu ve yönünü izler; üstte sıradaki dönüş ve ona kalan mesafe,
/// altta kalan süre ve mesafe. Dönüşe yaklaşınca sesli söyler; yoldan
/// çıkınca yolu yeniden bulur. Varınca "Vardın" ve Dinle.
struct GuidanceView: View {
    let destination: GuidanceDestination
    @EnvironmentObject private var store: AppStore
    @StateObject private var guide: WalkingGuide
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    init(destination: GuidanceDestination) {
        self.destination = destination
        _guide = StateObject(wrappedValue: WalkingGuide(destination: destination))
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
                if let route = guide.route {
                    // Yarı saydam: altındaki sokak adları ve ayrıntılar görünsün.
                    MapPolyline(route.polyline)
                        .stroke(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                }
                Annotation(destination.name, coordinate: destination.coordinate, anchor: .center) {
                    CategoryPin(category: destination.category, size: 36)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            // Pusula üstteki dönüş kartının arkasında kalıyordu; harita zaten yönüne dönüyor.
            .mapControls { }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                banner
                Spacer()
                if !position.followsUserLocation {
                    HStack {
                        Spacer()
                        CircleIconButton(systemImage: "location.north.line.fill") {
                            withAnimation { position = .userLocation(followsHeading: true, fallback: .automatic) }
                        }
                        .accessibilityLabel(Text("Konumuma dön"))
                    }
                }
                NarrationBar().padding(.horizontal, -12)
                bottomCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: guide.stepIndex)
        .animation(.snappy, value: guide.arrived)
        .onAppear {
            guide.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            guide.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Üst: sıradaki dönüş

    private var banner: some View {
        HStack(spacing: 14) {
            Image(systemName: guide.arrived ? "flag.checkered" : Self.symbol(for: guide.nextInstruction))
                .font(.system(size: 30, weight: .bold))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                if let distance = guide.distanceToNext, guide.status == .guiding, !guide.arrived {
                    Text(Self.formatted(distance)).font(Theme.font(26, .bold))
                }
                Text(bannerText)
                    .font(Theme.font(17, .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
        .softShadow()
        .padding(.top, 4)
    }

    private var bannerText: String {
        if guide.arrived { return String(localized: "Vardın: \(destination.name)") }
        switch guide.status {
        case .locating: return String(localized: "Konumun bulunuyor…")
        case .routing: return String(localized: "Yürüme yolu bulunuyor…")
        case .noRoute: return String(localized: "Yürüme yolu bulunamadı. İnternet bağlantını kontrol et.")
        case .denied: return String(localized: "Konum izni kapalı. Ayarlar'dan izin ver.")
        case .guiding: return guide.nextInstruction
        }
    }

    // MARK: - Alt: kalan süre, ses, bitir

    private var bottomCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if guide.arrived {
                    Text(destination.name).font(Theme.font(20, .bold)).lineLimit(1)
                } else if let meters = guide.remainingMeters {
                    Text("\(max(Int((meters / 1.3 / 60).rounded()), 1)) dk").font(Theme.font(22, .bold))
                    Text(verbatim: "\(Self.formatted(meters)) · \(destination.name)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                } else {
                    Text(destination.name).font(Theme.font(17, .semibold)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if guide.arrived, let place = destination.placeID.flatMap(store.place), place.wikipediaTitle != nil {
                PrimaryButton(title: "Dinle", systemImage: "play.fill") { Task { await listen(place) } }
            } else if guide.status == .denied {
                SecondaryButton(title: "Ayarları aç", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else {
                Button { guide.voiceOn.toggle() } label: {
                    Image(systemName: guide.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(guide.voiceOn ? LocalizedStringKey("Sesli yönlendirmeyi kapat") : LocalizedStringKey("Sesli yönlendirmeyi aç")))
            }
            Button { dismiss() } label: {
                Text("Bitir")
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .softShadow()
    }

    private func listen(_ place: Place) async {
        guard let title = place.wikipediaTitle,
              let summary = await WikipediaService.shared.summary(englishTitle: title) else { return }
        Narrator.shared.speak(summary.extract, title: place.name, language: summary.language)
    }

    // MARK: - Yardımcılar

    static func formatted(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// Talimattaki kelimelerden dönüş simgesi (Türkçe ve İngilizce).
    static func symbol(for instruction: String) -> String {
        let text = instruction.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("arrive", "destination", "varış", "vardın", "hedef") { return "mappin.circle.fill" }
        if has("u-turn", "geri dön") { return "arrow.uturn.down" }
        if has("slight left", "keep left", "hafif sol", "soldan devam") { return "arrow.up.left" }
        if has("slight right", "keep right", "hafif sağ", "sağdan devam") { return "arrow.up.right" }
        if has("left", "sola", "sol ") { return "arrow.turn.up.left" }
        if has("right", "sağa", "sağ ") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// Yol tarifinin işleyişi: konum, yol, sıradaki adım ve sesli yönlendirme.
@MainActor
final class WalkingGuide: NSObject, ObservableObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    enum Status: Equatable {
        case locating, routing, guiding, noRoute, denied
    }

    @Published private(set) var status: Status = .locating
    @Published private(set) var location: CLLocation?
    @Published private(set) var route: MKRoute?
    /// Şu an yüründüğü adım; sıradaki dönüş bir sonraki adımın talimatı.
    @Published private(set) var stepIndex = 0
    @Published private(set) var arrived = false
    @Published var voiceOn = true

    let destination: GuidanceDestination
    private let manager = CLLocationManager()
    private let speaker = AVSpeechSynthesizer()
    /// Dönüşü söylenmiş adımlar (bir kez söylenir).
    private var announced: Set<Int> = []
    private var offRouteCount = 0
    private var lastRouting: Date?
    private var resumeNarration = false

    /// Varış sayılan mesafe ve yoldan çıkmış sayılan uzaklık (metre).
    private let arrivalMeters: CLLocationDistance = 20
    private let offRouteMeters: CLLocationDistance = 45
    /// Dönüş bu kadar yaklaşınca söylenir.
    private let announceMeters: CLLocationDistance = 40

    init(destination: GuidanceDestination) {
        self.destination = destination
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        speaker.delegate = self
    }

    func start() {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            self.status = .denied
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        speaker.stopSpeaking(at: .immediate)
        resumeNarrationIfNeeded()
    }

    // MARK: - Ekrandaki bilgiler

    private var steps: [MKRoute.Step] { route?.steps ?? [] }

    var nextInstruction: String {
        let next = stepIndex + 1
        if steps.indices.contains(next), !steps[next].instructions.isEmpty {
            return steps[next].instructions
        }
        return String(localized: "Varış: \(destination.name)")
    }

    /// Sıradaki dönüşe (son adımdaysa varışa) kalan mesafe.
    var distanceToNext: CLLocationDistance? {
        guard let location else { return nil }
        if stepIndex + 1 < steps.count, let end = Self.end(of: steps[stepIndex].polyline) {
            return location.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        }
        return location.distance(from: destination.location)
    }

    var remainingMeters: CLLocationDistance? {
        guard let toNext = distanceToNext else { return nil }
        let later = steps.indices.filter { $0 > stepIndex }.reduce(0.0) { $0 + steps[$1].distance }
        return toNext + later
    }

    // MARK: - Konum

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.update(last) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted {
                self.status = .denied
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.status == .denied { self.status = .locating }
                self.manager.startUpdatingLocation()
            }
        }
    }

    private func update(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100, !arrived else { return }
        self.location = location
        if location.distance(from: destination.location) <= arrivalMeters {
            arrive()
            return
        }
        guard let route else {
            if status != .routing, (lastRouting.map { Date.now.timeIntervalSince($0) > 15 } ?? true) {
                Task { await findRoute(from: location) }
            }
            return
        }
        follow(location, on: route)
    }

    private func findRoute(from location: CLLocation) async {
        status = .routing
        lastRouting = .now
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .walking
        guard let found = try? await MKDirections(request: request).calculate().routes.first,
              !found.steps.isEmpty else {
            status = route == nil ? .noRoute : .guiding
            return
        }
        route = found
        // İlk adım çoğu zaman boş "yola çık" adımı; gerçek yürüyüşten başla.
        stepIndex = found.steps.count > 1 && found.steps[0].distance < 1 ? 1 : 0
        announced = []
        offRouteCount = 0
        status = .guiding
        let first = found.steps[stepIndex].instructions
        say(first.isEmpty ? nextInstruction : first)
    }

    /// Hangi adımda olduğunu bulur, dönüşe yaklaşınca söyler, yoldan çıkınca yolu yeniden bulur.
    private func follow(_ location: CLLocation, on route: MKRoute) {
        let steps = route.steps
        guard steps.indices.contains(stepIndex) else { return }
        // Sonraki iki adımın yoluna belirgin şekilde daha yakınsa ilerle.
        var best = stepIndex
        var bestDistance = Self.distance(from: location, to: steps[stepIndex].polyline)
        for index in (stepIndex + 1)..<min(stepIndex + 3, steps.count) {
            let distance = Self.distance(from: location, to: steps[index].polyline)
            if distance + 8 < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        if best > stepIndex {
            stepIndex = best
        } else if stepIndex + 1 < steps.count, let end = Self.end(of: steps[stepIndex].polyline),
                  location.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) < 10 {
            stepIndex += 1
        }

        // Yoldan çıktıysa (üç ölçüm üst üste) yolu yeniden bul.
        let offRoute = steps[stepIndex...].map { Self.distance(from: location, to: $0.polyline) }.min() ?? 0
        offRouteCount = offRoute > offRouteMeters ? offRouteCount + 1 : 0
        if offRouteCount >= 3, lastRouting.map({ Date.now.timeIntervalSince($0) > 10 }) ?? true {
            offRouteCount = 0
            say(String(localized: "Yol yeniden bulunuyor"))
            Task { await findRoute(from: location) }
            return
        }

        // Dönüşe yaklaşınca bir kez söyle.
        let next = stepIndex + 1
        if steps.indices.contains(next), !announced.contains(next),
           let distance = distanceToNext, distance <= announceMeters {
            announced.insert(next)
            say(steps[next].instructions)
        }
    }

    private func arrive() {
        arrived = true
        manager.stopUpdatingLocation()
        say(String(localized: "Vardın: \(destination.name)"))
    }

    // MARK: - Ses

    private func say(_ text: String) {
        guard voiceOn, !text.isEmpty else { return }
        let narrator = Narrator.shared
        if narrator.isSpeaking {
            narrator.togglePause()
            resumeNarration = true
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: text)
        speaker.speak(utterance)
    }

    private func resumeNarrationIfNeeded() {
        guard resumeNarration, !speaker.isSpeaking else { return }
        resumeNarration = false
        if Narrator.shared.isPaused { Narrator.shared.togglePause() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeNarrationIfNeeded() }
    }

    /// Talimat hangi dildeyse (Apple'ın talimatları telefonun dilinde) o dilin sesi.
    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
            ?? Locale.current.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(language) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    // MARK: - Geometri

    private static func end(of polyline: MKPolyline) -> CLLocationCoordinate2D? {
        polyline.pointCount > 0 ? polyline.points()[polyline.pointCount - 1].coordinate : nil
    }

    /// Bir noktanın çizgiye en kısa uzaklığı (metre).
    static func distance(from location: CLLocation, to polyline: MKPolyline) -> CLLocationDistance {
        let point = MKMapPoint(location.coordinate)
        let points = polyline.points()
        let count = polyline.pointCount
        guard count > 0 else { return .infinity }
        guard count > 1 else { return point.distance(to: points[0]) }
        var best = CLLocationDistance.infinity
        for index in 0..<(count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var t = lengthSquared > 0 ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared : 0
            t = min(max(t, 0), 1)
            best = min(best, point.distance(to: MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)))
        }
        return best
    }
}

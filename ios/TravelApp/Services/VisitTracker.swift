import CoreLocation
import Foundation

/// Gidilen yerleri konumdan bulur (Oguz, 2026-11-05): kayıtlı bir yerin
/// yanında birkaç dakika kalınca yer "Gittim" diye işaretlenir, haritada
/// pininde yeşil ✓ görünür. Konum telefondan dışarı gönderilmez.
///
/// - Uygulama açıkken: telefonun konumu ve çalan anlatım (`VisitDetector`:
///   durma, büyük yerde gezinme, yerin yanında anlatımı dinleme).
/// - Uygulama kapalıyken ("Her zaman" konum izni verildiyse): Apple'ın
///   pil dostu bölge izlemesi (en yakın 20 yer, 5 dakika kural) ve
///   "ziyaret" bildirimi (telefon bir yerde durunca). Bunlar uygulamayı
///   arka planda kısa süre uyandırır; bulunan yer, kayıtlar hazır değilse
///   saklanır ve uygulama açılınca işaretlenir.
@MainActor
final class VisitTracker: NSObject, CLLocationManagerDelegate {
    static let shared = VisitTracker()

    private let manager = CLLocationManager()
    private var detector = VisitDetector()
    private weak var store: AppStore?
    private var isForeground = false
    private var isUpdating = false
    /// Gidilmemiş kayıtlı yerler (uygulama kapalıyken açılırsa diye saklanır).
    private var targets: [VisitDetector.Target] = []
    /// Bölgeler en son bu konuma göre seçildi.
    private var regionsCenter: CLLocation?

    private let defaults = UserDefaults.standard
    private static let targetsKey = "visits.targets"
    private static let pendingKey = "visits.pending"
    private static let enteredKey = "visits.entered"
    private static let askedAlwaysKey = "visits.askedAlways"

    override private init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        targets = (defaults.data(forKey: Self.targetsKey))
            .flatMap { try? JSONDecoder().decode([VisitDetector.Target].self, from: $0) } ?? []
    }

    /// Uygulama açılırken çağrılır (Apple uygulamayı bir bölge olayı için
    /// arka planda açtığında da): konum yöneticisi hazır olsun ki olay kaybolmasın.
    func activate() {
        startBackgroundMonitoring()
    }

    /// Kayıtlar hazır: bekleyen işaretler uygulanır, uygulama kapalıyken de
    /// çalışması için bir kez "Her zaman" izni istenir.
    func attach(_ store: AppStore) {
        self.store = store
        refresh()
        requestAlwaysOnce()
    }

    /// Kayıtlı yerler değişince (yer eklendi, gidildi, silindi) izlenen
    /// yerler yenilenir.
    func refresh() {
        guard let store else { return }
        applyPending()
        targets = store.places.filter { $0.visitedAt == nil }.map(VisitDetector.target(for:))
        if let data = try? JSONEncoder().encode(targets) { defaults.set(data, forKey: Self.targetsKey) }
        updateRegions(around: manager.location, force: true)
        if isForeground { startUpdates() }
    }

    /// Uygulama öne gelince konum izlenir, arkaya gidince bırakılır
    /// (arkada yalnızca Apple'ın pil dostu izlemesi).
    func setForeground(_ active: Bool) {
        isForeground = active
        if active {
            applyPending()
            startUpdates()
        } else {
            stopUpdates()
        }
    }

    // MARK: - Uygulama açıkken

    private var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    private func startUpdates() {
        #if DEBUG
        if defaults.string(forKey: "screen") != nil { return }
        #endif
        guard isAuthorized, !targets.isEmpty else { return stopUpdates() }
        guard !isUpdating else { return }
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.startUpdatingLocation()
        isUpdating = true
    }

    private func stopUpdates() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    private func handle(_ location: CLLocation) {
        if isForeground {
            // Yerin anlatımı yerin yanında dinleniyorsa bu da gidildiğini gösterir.
            let narrator = Narrator.shared
            let narrating = narrator.isSpeaking ? narrator.currentTitle : nil
            let found = detector.update(location, targets: targets, narrating: narrating)
            if !found.isEmpty { record(Dictionary(uniqueKeysWithValues: found.map { ($0, location.timestamp) })) }
            // Pil: gidilmemiş en yakın yer uzaksa konum seyrek ve kaba istenir.
            let nearest = targets.map { location.distance(from: $0.location) }.min() ?? .infinity
            let far = nearest > 2_000
            manager.desiredAccuracy = far ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = far ? 100 : kCLDistanceFilterNone
        }
        updateRegions(around: location, force: false)
    }

    // MARK: - Uygulama kapalıyken

    private var hasAlways: Bool { manager.authorizationStatus == .authorizedAlways }

    private func startBackgroundMonitoring() {
        guard hasAlways else { return }
        manager.startMonitoringVisits()
        // Şehirde ~500 m yer değiştirince uyanıp en yakın 20 yeri yeniden seçer.
        manager.startMonitoringSignificantLocationChanges()
        updateRegions(around: manager.location, force: true)
    }

    /// Uygulama kapalıyken çalışsın diye bir kez "Her zaman" izni (iPhone
    /// "Her Zaman İzin Ver'e geç" diye sorar; kullanıcı istemezse yalnızca
    /// uygulama açıkken çalışır).
    private func requestAlwaysOnce() {
        #if DEBUG
        if defaults.string(forKey: "screen") != nil { return }
        #endif
        guard manager.authorizationStatus == .authorizedWhenInUse, !defaults.bool(forKey: Self.askedAlwaysKey),
              let store, store.trips.contains(where: { !$0.placeIDs.isEmpty }) else { return }
        defaults.set(true, forKey: Self.askedAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    /// En yakın 20 gidilmemiş yer için bölge (Apple'ın sınırı 20).
    private func updateRegions(around location: CLLocation?, force: Bool) {
        guard hasAlways, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        if !force, let regionsCenter, let location, location.distance(from: regionsCenter) < 300 { return }
        regionsCenter = location ?? regionsCenter
        let wanted = location.map { VisitDetector.nearest(targets, to: $0) }
            ?? Array(targets.prefix(VisitDetector.regionLimit))
        let wantedIDs = Set(wanted.map(\.id.uuidString))
        for region in manager.monitoredRegions where !wantedIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        let current = Set(manager.monitoredRegions.map(\.identifier))
        for target in wanted where !current.contains(target.id.uuidString) {
            let region = CLCircularRegion(center: target.coordinate,
                                          radius: max(target.radius, VisitDetector.minRegionRadius),
                                          identifier: target.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func entered(_ id: String, at date: Date) {
        var entered = defaults.dictionary(forKey: Self.enteredKey) as? [String: Double] ?? [:]
        entered[id] = date.timeIntervalSince1970
        defaults.set(entered, forKey: Self.enteredKey)
    }

    private func exited(_ id: String, at date: Date) {
        var entered = defaults.dictionary(forKey: Self.enteredKey) as? [String: Double] ?? [:]
        let since = entered.removeValue(forKey: id).map { Date(timeIntervalSince1970: $0) }
        defaults.set(entered, forKey: Self.enteredKey)
        if let since, let uuid = UUID(uuidString: id), VisitDetector.regionVisit(enteredAt: since, exitedAt: date) {
            record([uuid: since])
        }
    }

    private func visited(at coordinate: CLLocationCoordinate2D, accuracy: CLLocationAccuracy, arrival: Date) {
        guard arrival != .distantPast,
              let id = VisitDetector.match(visit: coordinate, accuracy: accuracy, targets: targets) else { return }
        record([id: arrival])
    }

    // MARK: - İşaretleme

    /// Bulunan yerler işaretlenir; kayıtlar hazır değilse (uygulama arka
    /// planda açıldı) saklanır, açılınca işaretlenir.
    private func record(_ visits: [UUID: Date]) {
        let found = Set(visits.keys)
        targets.removeAll { found.contains($0.id) }
        if let store {
            store.markVisited(visits)
        } else {
            var pending = defaults.dictionary(forKey: Self.pendingKey) as? [String: Double] ?? [:]
            for (id, date) in visits { pending[id.uuidString] = date.timeIntervalSince1970 }
            defaults.set(pending, forKey: Self.pendingKey)
        }
    }

    private func applyPending() {
        guard let store, let pending = defaults.dictionary(forKey: Self.pendingKey) as? [String: Double],
              !pending.isEmpty else { return }
        defaults.removeObject(forKey: Self.pendingKey)
        var visits: [UUID: Date] = [:]
        for (id, time) in pending {
            if let uuid = UUID(uuidString: id) { visits[uuid] = Date(timeIntervalSince1970: time) }
        }
        store.markVisited(visits)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.handle(last) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.startBackgroundMonitoring()
            if self.isForeground { self.startUpdates() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.entered(id, at: Date()) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.exited(id, at: Date()) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let coordinate = visit.coordinate
        let accuracy = visit.horizontalAccuracy
        let arrival = visit.arrivalDate
        Task { @MainActor in self.visited(at: coordinate, accuracy: accuracy, arrival: arrival) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {}
}

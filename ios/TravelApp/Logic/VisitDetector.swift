import CoreLocation
import Foundation

/// "Gittim" işareti (Oguz, 2026-11-05): kayıtlı bir yere (rotadaki ya da
/// haritadaki) gidildiği konumdan anlaşılır, haritada yeşil ✓ ile görünür.
/// Kararlar burada (test edilebilir); konumu `VisitTracker` verir.
///
/// Kurallar benzer uygulamalardan (Oguz'un "optimize et" kuralı, 2026-11-05):
/// - **Durma** (Radar: 70 m içinde 140 sn kalan telefon "durdu" sayılır;
///   Foursquare: bir yerde en az 2 dakika kalınca ziyaret): telefon 70 m
///   içinde 140 saniye kalınca durduğu yerin ortasına **en yakın** kayıtlı
///   yer gidildi olur (Foursquare'in "en olası yere oturtma"sı gibi; yan
///   yana iki kafeden yalnızca biri).
/// - **Gezinme** (Google'ın bölgede "oyalanma" bildirimi gibi): park, müze,
///   tapınak gibi büyük yerlerde durmadan dolaşılır; yerin çevresinde 5
///   dakika kalmak yeter.
/// - **Dinleme** (Oguz'un önerisi; sesli rehberler anlatımı yerin yanında
///   çalar): yerin anlatımı yerin yakınındayken en az 1 dakika dinlenirse.
///
/// Yanından yürüyüp geçmek sayılmaz: yürürken 70 m'lik daire 1 dakikada
/// geride kalır. Belirsiz konum (bina içinde kötü sinyal) kullanılmaz.
struct VisitDetector {
    /// İzlenen bir yer (uygulama kapalıyken de kullanılsın diye saklanır).
    struct Target: Codable, Equatable, Identifiable {
        var id: UUID
        var latitude: Double
        var longitude: Double
        /// Yerin yakını sayılan çember (m).
        var radius: Double
        /// Yerin adı: anlatım (Dinle) bu adla çalar.
        var name: String?

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    // Durma (Radar'ın "responsive" ayarı: stopDuration 140, stopDistance 70).
    static let stopDuration: TimeInterval = 140
    static let stopDistance: CLLocationDistance = 70
    /// Daireden bundan uzun dışarıda kalınca yeni durma aranır (tek sapan konum sayılmaz).
    static let moveGrace: TimeInterval = 20
    /// Durulan yerin ortası yere bu kadar (konumun belirsizliği kadar, en çok) uzak olabilir.
    static let maxSlack: CLLocationDistance = 50

    // Gezinme (büyük yerler).
    static let wanderDwell: TimeInterval = 300
    /// Bu yarıçap ve üstü "büyük yer" (park, müze, tapınak, manzara).
    static let wanderRadius: CLLocationDistance = 100
    /// Çemberin bu kadar dışı da "hâlâ orada" sayılır (konum titremesi).
    static let leaveMargin: CLLocationDistance = 25
    /// Bundan uzun uzakta kalınca gezinme sayacı sıfırlanır.
    static let farGrace: TimeInterval = 45

    // Dinleme.
    static let listenDuration: TimeInterval = 60
    /// Anlatım dinlenirken yerin çemberinden bu kadar dışı da yakın sayılır
    /// (anlatım yere yaklaşınca başlar, karşı kaldırımdan da dinlenir).
    static let listenMargin: CLLocationDistance = 50

    /// Bundan belirsiz konum (m) kullanılmaz. Google: Wi-Fi konumu genelde
    /// 20-50 m; bina içinde 50 m varsayılmalı.
    static let maxAccuracy: CLLocationAccuracy = 65
    /// Arada bu kadar konum gelmezse (uygulama arkadaydı) sayaçlar baştan.
    static let maxGap: TimeInterval = 300

    /// Uygulama kapalıyken Apple'ın bölge izlemesi (Google'ın "oyalanma"
    /// bildirimi gibi): girip çıkma arası en az bu kadar (yanından geçmek,
    /// çıkış gecikmesiyle 3-4 dakika sürebiliyor).
    static let regionDwell: TimeInterval = 300
    /// Bundan uzun "içeride" kalış çıkış olayının kaçtığını gösterir; sayılmaz.
    static let regionMaxStay: TimeInterval = 12 * 3600
    /// Apple'ın bir uygulama için aynı anda izlediği en çok bölge.
    static let regionLimit = 20
    /// Bölge izlemede en küçük yarıçap (Google: en az 100-150 m).
    static let minRegionRadius: CLLocationDistance = 100
    /// Bundan uzak yerler için bölge kurulmaz (başka şehir).
    static let regionRange: CLLocationDistance = 30_000

    /// Yerin yakını sayılan çember: büyük yerlerde (park, tapınak alanı)
    /// geniş, kafe ve restoranda dar.
    static func radius(for category: PlaceCategory) -> CLLocationDistance {
        switch category {
        case .park: 200
        case .sight, .temple, .museum, .viewpoint: 100
        case .food, .cafe, .shopping, .bar, .hotel, .other: 50
        }
    }

    static func target(for place: Place) -> Target {
        Target(id: place.id, latitude: place.latitude, longitude: place.longitude,
               radius: radius(for: place.category), name: place.name)
    }

    /// Şu anki durma: başladığı yer ve an; içindeki konumların ortası
    /// (yer eşlemesi için; tek konumun sapması ortayı az kaydırır).
    private struct Stop {
        /// Dairenin merkezi: durmanın ilk konumu (yürürken daire geride kalsın).
        var anchor: CLLocation
        var since: Date
        var latitude = 0.0
        var longitude = 0.0
        var count = 0
        var matched = false
        /// Daireden çıkılan ilk konum (sürerse yeni durma oradan başlar).
        var movedAt: (location: CLLocation, time: Date)?

        init(_ location: CLLocation, at time: Date) {
            anchor = location
            since = time
            add(location)
        }

        mutating func add(_ location: CLLocation) {
            latitude += location.coordinate.latitude
            longitude += location.coordinate.longitude
            count += 1
        }

        var center: CLLocation { CLLocation(latitude: latitude / Double(count), longitude: longitude / Double(count)) }
    }

    private struct Stay {
        var since: Date
        var farSince: Date?
    }

    private var stop: Stop?
    private var stays: [UUID: Stay] = [:]
    private var listened: [UUID: TimeInterval] = [:]
    private var lastSample: Date?
    /// Bir kez bildirilen yer yeniden bildirilmez.
    private var reported: Set<UUID> = []

    /// Yeni konum: gidildiği anlaşılan yerler (her biri bir kez).
    /// `narrating`: o an çalan anlatımın adı (duraklatılmışsa nil).
    mutating func update(_ location: CLLocation, targets: [Target], now: Date? = nil,
                         narrating: String? = nil) -> [UUID] {
        let now = now ?? location.timestamp
        let step = lastSample.map { now.timeIntervalSince($0) } ?? 0
        // Uzun süre konum gelmediyse (uygulama arkadaydı) eski sayaçlar geçersiz.
        if step > Self.maxGap {
            stop = nil
            stays = [:]
        }
        lastSample = now
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maxAccuracy else { return [] }
        let open = targets.filter { !reported.contains($0.id) }
        var visited: [UUID] = []
        if let id = updateStop(location, now: now, targets: open) { visited.append(id) }
        visited += updateStays(location, now: now, targets: open.filter { $0.radius >= Self.wanderRadius })
        if let narrating {
            visited += updateListening(location, step: min(max(step, 0), 5), title: narrating, targets: open)
        }
        let unique = Array(Set(visited))
        reported.formUnion(unique)
        return unique
    }

    /// Durma: 70 m içinde 140 sn; durulan yerin ortasına en yakın yer.
    private mutating func updateStop(_ location: CLLocation, now: Date, targets: [Target]) -> UUID? {
        guard var current = stop else {
            stop = Stop(location, at: now)
            return nil
        }
        if location.distance(from: current.anchor) <= Self.stopDistance {
            current.movedAt = nil
            current.add(location)
        } else if let moved = current.movedAt {
            // Daireden 20 sn'den uzun dışarıda: yeni durma ilk çıkılan yerden başlar.
            if now.timeIntervalSince(moved.time) > Self.moveGrace {
                var next = Stop(moved.location, at: moved.time)
                if location.distance(from: next.anchor) <= Self.stopDistance {
                    next.add(location)
                } else {
                    next.movedAt = (location, now)
                }
                stop = next
                return nil
            }
        } else {
            current.movedAt = (location, now)
        }
        var found: UUID?
        if !current.matched, current.movedAt == nil, now.timeIntervalSince(current.since) >= Self.stopDuration {
            let slack = min(location.horizontalAccuracy, Self.maxSlack)
            found = Self.nearest(to: current.center, slack: slack, targets: targets)
            current.matched = found != nil
        }
        stop = current
        return found
    }

    /// Gezinme: büyük yerin çevresinde 5 dakika (kısa sapmalar sayacı bozmaz).
    private mutating func updateStays(_ location: CLLocation, now: Date, targets: [Target]) -> [UUID] {
        var visited: [UUID] = []
        var kept: [UUID: Stay] = [:]
        for target in targets {
            let distance = location.distance(from: target.location)
            guard var stay = stays[target.id] else {
                if distance <= target.radius { kept[target.id] = Stay(since: now) }
                continue
            }
            if distance <= target.radius + Self.leaveMargin {
                stay.farSince = nil
                if now.timeIntervalSince(stay.since) >= Self.wanderDwell {
                    visited.append(target.id)
                } else {
                    kept[target.id] = stay
                }
            } else {
                let farSince = stay.farSince ?? now
                // Kısa sapma: sayaç sürer (ama uzaktayken gidildi sayılmaz).
                if now.timeIntervalSince(farSince) <= Self.farGrace {
                    stay.farSince = farSince
                    kept[target.id] = stay
                }
            }
        }
        stays = kept
        return visited
    }

    /// Dinleme: yerin anlatımı yerin yakınındayken 1 dakika çaldıysa.
    private mutating func updateListening(_ location: CLLocation, step: TimeInterval, title: String,
                                          targets: [Target]) -> [UUID] {
        var visited: [UUID] = []
        for target in targets where target.name?.caseInsensitiveCompare(title) == .orderedSame {
            guard location.distance(from: target.location) <= target.radius + Self.listenMargin else { continue }
            let total = (listened[target.id] ?? 0) + step
            listened[target.id] = total
            if total >= Self.listenDuration { visited.append(target.id) }
        }
        return visited
    }

    /// Durulan yerin ortasına en yakın, çemberinin içindeki yer.
    private static func nearest(to center: CLLocation, slack: CLLocationDistance, targets: [Target]) -> UUID? {
        var best: (id: UUID, distance: CLLocationDistance)?
        for target in targets {
            let distance = center.distance(from: target.location)
            guard distance <= target.radius + slack, distance < (best?.distance ?? .infinity) else { continue }
            best = (target.id, distance)
        }
        return best?.id
    }

    /// Uygulama kapalıyken: bölgeye girip çıkma arası yeterince uzunsa gidildi.
    static func regionVisit(enteredAt: Date?, exitedAt: Date) -> Bool {
        guard let enteredAt else { return false }
        let stay = exitedAt.timeIntervalSince(enteredAt)
        return stay >= regionDwell && stay <= regionMaxStay
    }

    /// Apple'ın "ziyaret" bildirimi (telefon bir yerde durunca; Apple'ın
    /// kendi durma algılaması): çemberin içindeki en yakın yer. Konum çok
    /// belirsizse hiçbiri.
    static func match(visit coordinate: CLLocationCoordinate2D, accuracy: CLLocationAccuracy,
                      targets: [Target]) -> UUID? {
        guard accuracy >= 0, accuracy <= 150 else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return nearest(to: location, slack: min(accuracy, maxSlack), targets: targets)
    }

    /// Uygulama kapalıyken izlenecek bölgeler: konuma en yakın yerler.
    static func nearest(_ targets: [Target], to location: CLLocation, limit: Int = regionLimit) -> [Target] {
        let near = targets
            .map { (target: $0, distance: location.distance(from: $0.location)) }
            .filter { $0.distance <= regionRange }
            .sorted { $0.distance < $1.distance }
        return near.prefix(limit).map(\.target)
    }
}

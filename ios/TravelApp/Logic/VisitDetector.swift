import CoreLocation
import Foundation

/// "Gittim" işareti (Oguz, 2026-11-05): kayıtlı bir yerin (rotadaki ya da
/// haritadaki) yanında bir süre kalınca yer "gidildi" sayılır ve haritada
/// yeşil ✓ ile görünür. Kararlar burada (test edilebilir); konumu
/// `VisitTracker` verir.
///
/// Yanından yürüyüp geçmek sayılmaz: yerin çevresinde (kafe 40 m, müze ve
/// tapınak 80 m, park 150 m) en az 3 dakika kalmak gerekir. Bir anlık
/// sapan konum sayacı sıfırlamaz; 45 saniyeden uzun uzaklaşınca sıfırlanır.
struct VisitDetector {
    /// İzlenen bir yer (uygulama kapalıyken de kullanılsın diye saklanır).
    struct Target: Codable, Equatable, Identifiable {
        var id: UUID
        var latitude: Double
        var longitude: Double
        /// Yerin yakını sayılan çember (m).
        var radius: Double

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// Uygulama açıkken yerin yakınında bu kadar kalınca gidildi sayılır.
    static let dwell: TimeInterval = 180
    /// Çemberin bu kadar dışı da "hâlâ orada" sayılır (konum titremesi).
    static let leaveMargin: CLLocationDistance = 25
    /// Bundan uzun uzakta kalınca sayaç sıfırlanır.
    static let farGrace: TimeInterval = 45
    /// Bundan belirsiz konum (m) kullanılmaz (bina içinde kötü sinyal).
    static let maxAccuracy: CLLocationAccuracy = 65
    /// Arada bu kadar konum gelmezse (uygulama arkadaydı) sayaç baştan.
    static let maxGap: TimeInterval = 300

    /// Uygulama kapalıyken Apple'ın bölge izlemesi: girip çıkma arası en az
    /// bu kadar (yanından geçmek, çıkış gecikmesiyle 3-4 dakika sürebiliyor).
    static let regionDwell: TimeInterval = 300
    /// Bundan uzun "içeride" kalış çıkış olayının kaçtığını gösterir; sayılmaz.
    static let regionMaxStay: TimeInterval = 12 * 3600
    /// Apple'ın bir uygulama için aynı anda izlediği en çok bölge.
    static let regionLimit = 20
    /// Bölge izlemede en küçük yarıçap (daha küçüğü güvenilir tetiklenmiyor).
    static let minRegionRadius: CLLocationDistance = 100
    /// Bundan uzak yerler için bölge kurulmaz (başka şehir).
    static let regionRange: CLLocationDistance = 30_000

    /// Yerin yakını sayılan çember: büyük yerlerde (park, tapınak alanı)
    /// geniş, kafe ve restoranda dar.
    static func radius(for category: PlaceCategory) -> CLLocationDistance {
        switch category {
        case .park: 150
        case .sight, .temple, .museum, .viewpoint: 80
        case .food, .cafe, .shopping, .bar, .hotel, .other: 40
        }
    }

    static func target(for place: Place) -> Target {
        Target(id: place.id, latitude: place.latitude, longitude: place.longitude,
               radius: radius(for: place.category))
    }

    private struct Stay {
        var since: Date
        var farSince: Date?
    }

    private var stays: [UUID: Stay] = [:]
    private var lastSample: Date?

    /// Yeni konum: yakınında yeterince kalınan yerler (her biri bir kez).
    mutating func update(_ location: CLLocation, targets: [Target], now: Date? = nil) -> [UUID] {
        let now = now ?? location.timestamp
        // Uzun süre konum gelmediyse (uygulama arkadaydı) eski sayaçlar geçersiz.
        if let lastSample, now.timeIntervalSince(lastSample) > Self.maxGap { stays = [:] }
        lastSample = now
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maxAccuracy else { return [] }

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
                if now.timeIntervalSince(stay.since) >= Self.dwell {
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

    /// Uygulama kapalıyken: bölgeye girip çıkma arası yeterince uzunsa gidildi.
    static func regionVisit(enteredAt: Date?, exitedAt: Date) -> Bool {
        guard let enteredAt else { return false }
        let stay = exitedAt.timeIntervalSince(enteredAt)
        return stay >= regionDwell && stay <= regionMaxStay
    }

    /// Apple'ın "ziyaret" bildirimi (telefon bir yerde bir süre durunca):
    /// çemberin içindeki en yakın yer. Konum çok belirsizse hiçbiri.
    static func match(visit coordinate: CLLocationCoordinate2D, accuracy: CLLocationAccuracy,
                      targets: [Target]) -> UUID? {
        guard accuracy >= 0, accuracy <= 150 else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let slack = min(accuracy, 50)
        var best: (id: UUID, distance: CLLocationDistance)?
        for target in targets {
            let distance = location.distance(from: target.location)
            guard distance <= target.radius + slack, distance < (best?.distance ?? .infinity) else { continue }
            best = (target.id, distance)
        }
        return best?.id
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

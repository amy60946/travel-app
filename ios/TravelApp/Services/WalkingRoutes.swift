import CoreLocation
import Foundation

/// Bir günün durakları arasındaki yürüyüş yolu (Google Routes). Duraklar
/// tek istekte gider (en çok 11 durak; fazlası parça parça). Bulunan yollar
/// telefonda 30 gün saklanır (internetsiz yürüyüş için; Google'ın saklama
/// sınırı). Yol bulunamazsa duraklar düz çizgiyle birleşir.
@MainActor
enum WalkingRoutes {
    struct DayRoute {
        var lines: [[CLLocationCoordinate2D]]
        var meters: Double
        var minutes: Int
    }

    private struct Stored: Codable {
        var legs: [[[Double]]]
        var meters: Double
        var seconds: Double
        var savedAt: Date
    }

    private static let cache = DiskCache<Stored>(name: "walking-routes-google")
    private static let keepFor: TimeInterval = 30 * 86_400

    static func route(through stops: [Place]) async -> DayRoute {
        var lines: [[CLLocationCoordinate2D]] = []
        var meters = 0.0
        var seconds = 0.0
        var start = 0
        while start < stops.count - 1 {
            let end = min(start + GoogleRoutes.maxPoints - 1, stops.count - 1)
            let chunk = Array(stops[start...end])
            if let found = await route(chunk) {
                lines += found.legs
                meters += found.meters
                seconds += found.seconds
            } else {
                // Yol bulunamazsa düz çizgi ve kabaca 5 km/sa.
                for (from, to) in zip(chunk, chunk.dropFirst()) {
                    lines.append([from.coordinate, to.coordinate])
                    let distance = from.location.distance(from: to.location)
                    meters += distance
                    seconds += distance / 1.4
                }
            }
            start = end
        }
        return DayRoute(lines: lines, meters: meters, minutes: Int(seconds / 60))
    }

    private static func route(_ stops: [Place]) async -> (legs: [[CLLocationCoordinate2D]], meters: Double, seconds: Double)? {
        let key = stops.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ">")
        if let stored = cache[key], Date.now.timeIntervalSince(stored.savedAt) < keepFor {
            let legs = stored.legs.map { $0.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }
            return (legs, stored.meters, stored.seconds)
        }
        guard let route = await GoogleRoutes.walking(through: stops.map(\.coordinate)) else { return nil }
        cache[key] = Stored(legs: route.legs.map { $0.map { [$0.latitude, $0.longitude] } },
                            meters: route.meters, seconds: route.seconds, savedAt: .now)
        return (route.legs, route.meters, route.seconds)
    }
}

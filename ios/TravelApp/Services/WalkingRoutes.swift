import MapKit

/// Duraklar arası yürüyüş yolu (Apple Haritalar, ücretsiz).
@MainActor
enum WalkingRoutes {
    struct DayRoute {
        var polylines: [MKPolyline]
        var meters: Double
        var minutes: Int
    }

    private static var cache: [String: MKRoute] = [:]

    static func route(through stops: [Place]) async -> DayRoute {
        var polylines: [MKPolyline] = []
        var meters = 0.0
        var seconds = 0.0
        for (from, to) in zip(stops, stops.dropFirst()) {
            if let leg = await leg(from: from, to: to) {
                polylines.append(leg.polyline)
                meters += leg.distance
                seconds += leg.expectedTravelTime
            } else {
                // Yol bulunamazsa düz çizgi ve kabaca 5 km/sa.
                polylines.append(MKPolyline(coordinates: [from.coordinate, to.coordinate], count: 2))
                let distance = from.location.distance(from: to.location)
                meters += distance
                seconds += distance / 1.4
            }
        }
        return DayRoute(polylines: polylines, meters: meters, minutes: Int(seconds / 60))
    }

    private static func leg(from: Place, to: Place) async -> MKRoute? {
        let key = "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)"
        if let cached = cache[key] { return cached }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        cache[key] = route
        return route
    }
}

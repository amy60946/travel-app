import MapKit

/// Duraklar arası yürüyüş yolu (Apple Haritalar, ücretsiz).
@MainActor
enum WalkingRoutes {
    struct DayRoute {
        var polylines: [MKPolyline]
        var meters: Double
        var minutes: Int
    }

    /// Bulunan yollar telefonda saklanır; internetsiz yürüyüşte buradan okunur.
    private struct Leg: Codable {
        var coordinates: [[Double]]
        var meters: Double
        var seconds: Double

        var polyline: MKPolyline {
            let points = coordinates.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            return MKPolyline(coordinates: points, count: points.count)
        }
    }

    private static let cache = DiskCache<Leg>(name: "walking-routes")

    static func route(through stops: [Place]) async -> DayRoute {
        var polylines: [MKPolyline] = []
        var meters = 0.0
        var seconds = 0.0
        for (from, to) in zip(stops, stops.dropFirst()) {
            if let leg = await leg(from: from, to: to) {
                polylines.append(leg.polyline)
                meters += leg.meters
                seconds += leg.seconds
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

    private static func leg(from: Place, to: Place) async -> Leg? {
        let key = "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)"
        if let cached = cache[key] { return cached }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
        route.polyline.getCoordinates(&points, range: NSRange(location: 0, length: points.count))
        let leg = Leg(coordinates: points.map { [$0.latitude, $0.longitude] },
                      meters: route.distance, seconds: route.expectedTravelTime)
        cache[key] = leg
        return leg
    }
}

import CoreLocation
import Foundation

/// Google Routes: yürüyüş yolu (ayda 10.000 istek ücretsiz). Talimatlar
/// uygulamanın dilinde gelir ("Sola dönün"). Bir istekte en çok 11 nokta
/// (9'dan fazla ara durak ücretli katmana geçer).
enum GoogleRoutes {
    struct Step {
        /// "Meiji-dori'ye doğru sağa dönün".
        var instruction: String
        /// Google'ın dönüş türü ("TURN_LEFT", "STRAIGHT"...).
        var maneuver: String?
        var meters: Double
        var coordinates: [CLLocationCoordinate2D]
    }

    struct Route {
        /// Ardışık iki nokta arasındaki yollar.
        var legs: [[CLLocationCoordinate2D]]
        var steps: [Step]
        var meters: Double
        var seconds: Double

        var coordinates: [CLLocationCoordinate2D] { legs.flatMap { $0 } }
    }

    static let maxPoints = 11

    static func walking(through points: [CLLocationCoordinate2D]) async -> Route? {
        guard points.count >= 2, points.count <= maxPoints else { return nil }
        func waypoint(_ coordinate: CLLocationCoordinate2D) -> [String: Any] {
            ["location": ["latLng": ["latitude": coordinate.latitude, "longitude": coordinate.longitude]]]
        }
        var body: [String: Any] = [
            "origin": waypoint(points[0]),
            "destination": waypoint(points[points.count - 1]),
            "travelMode": "WALK",
            "languageCode": GoogleAPI.language,
            "units": "METRIC",
        ]
        if points.count > 2 { body["intermediates"] = points.dropFirst().dropLast().map(waypoint) }
        let fields = "routes.distanceMeters,routes.duration,routes.legs.polyline.encodedPolyline,"
            + "routes.legs.steps.distanceMeters,routes.legs.steps.polyline.encodedPolyline,"
            + "routes.legs.steps.navigationInstruction"
        guard let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes"),
              let request = try? GoogleAPI.request(url, fields: fields, body: body),
              let response = try? await GoogleAPI.fetch(Response.self, request),
              let route = response.routes?.first else { return nil }
        let legs = (route.legs ?? []).map { GoogleAPI.decodePolyline($0.polyline?.encodedPolyline ?? "") }
        let steps = (route.legs ?? []).flatMap { $0.steps ?? [] }.map { step in
            Step(instruction: step.navigationInstruction?.instructions ?? "",
                 maneuver: step.navigationInstruction?.maneuver,
                 meters: step.distanceMeters ?? 0,
                 coordinates: GoogleAPI.decodePolyline(step.polyline?.encodedPolyline ?? ""))
        }
        let seconds = Double(route.duration?.replacingOccurrences(of: "s", with: "") ?? "") ?? (route.distanceMeters ?? 0) / 1.4
        return Route(legs: legs, steps: steps, meters: route.distanceMeters ?? 0, seconds: seconds)
    }

    private struct Response: Decodable {
        var routes: [RawRoute]?
    }

    private struct RawRoute: Decodable {
        var distanceMeters: Double?
        var duration: String?
        var legs: [RawLeg]?
    }

    private struct RawLeg: Decodable {
        var polyline: Polyline?
        var steps: [RawStep]?
    }

    private struct Polyline: Decodable {
        var encodedPolyline: String?
    }

    private struct RawStep: Decodable {
        var distanceMeters: Double?
        var polyline: Polyline?
        var navigationInstruction: Instruction?
    }

    private struct Instruction: Decodable {
        var maneuver: String?
        var instructions: String?
    }
}

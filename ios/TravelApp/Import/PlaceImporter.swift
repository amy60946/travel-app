import CoreLocation
import MapKit

/// Veri dosyasından gelen kayıtları yere çevirir: koordinatsızları Apple
/// Haritalar'da arar, her yeri bir şehre bağlar.
@MainActor
final class PlaceImporter: ObservableObject {
    struct Result {
        var added: [Place] = []
        var notFound: [String] = []
    }

    @Published private(set) var progress: (done: Int, total: Int)?

    /// Bu mesafedeki yerler aynı şehre sayılır.
    private let cityRadius: CLLocationDistance = 40_000
    private let geocoder = CLGeocoder()

    func resolve(_ items: [TakeoutParser.Item], knownCities: [AppStore.CitySummary]) async -> Result {
        var result = Result()
        var cities: [(name: String, location: CLLocation)] = knownCities.map {
            ($0.name, CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }
        progress = (0, items.count)
        defer { progress = nil }

        for (index, item) in items.enumerated() {
            progress = (index, items.count)
            var coordinate: CLLocationCoordinate2D?
            var estimated = false
            if let lat = item.latitude, let lon = item.longitude {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let found = await search(item) {
                coordinate = found
                estimated = true
            }
            guard let coordinate else {
                result.notFound.append(item.name)
                continue
            }

            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            var city = cities.first { $0.location.distance(from: location) < cityRadius }?.name
            if city == nil, let name = await cityName(at: location) {
                city = name
                cities.append((name, location))
            }

            result.added.append(Place(
                name: item.name, city: city ?? String(localized: "Diğer"),
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                category: .sight, source: item.source, isEstimated: estimated, note: item.note,
                sourceURL: item.url))
        }
        return result
    }

    private func search(_ item: TakeoutParser.Item) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [item.name, item.address].compactMap { $0 }.joined(separator: ", ")
        request.resultTypes = .pointOfInterest
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first?.placemark.coordinate
    }

    /// Konumun şehri: bilinen bir şehre yakınsa o, değilse haritadan bulunan ad.
    func city(for location: CLLocation, knownCities: [AppStore.CitySummary]) async -> String {
        if let near = knownCities.first(where: {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) < cityRadius
        }) {
            return near.name
        }
        return await cityName(at: location) ?? String(localized: "Diğer")
    }

    /// Şehir adı. Japonya gibi ülkelerde ilçe yerine il (ör. Tokyo) seçilir.
    private func cityName(at location: CLLocation) async -> String? {
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        guard let placemark else { return nil }
        if placemark.isoCountryCode == "JP" {
            return (placemark.administrativeArea ?? placemark.locality)?
                .replacingOccurrences(of: " Prefecture", with: "")
                .replacingOccurrences(of: "-to", with: "")
        }
        return placemark.locality ?? placemark.administrativeArea
    }
}

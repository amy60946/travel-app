import MapKit

/// Şehir ve ülke arama (yeni gezi ve Keşfet): şehirler Apple Haritalar'dan
/// (ücretsiz, telefonun dilinde), ülkeler uygulamadaki listeden.
@MainActor
final class CitySearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { update() }
    }
    @Published private(set) var cities: [MKLocalSearchCompletion] = []
    @Published private(set) var countries: [Country] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    private func update() {
        let text = query.trimmingCharacters(in: .whitespaces)
        countries = Array(Country.matching(text).prefix(4))
        if text.isEmpty {
            completer.cancel()
            cities = []
            isSearching = false
        } else {
            isSearching = true
            completer.queryFragment = text
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            // Ülkeler listede ayrıca var; sokak adresleri (numaralı) alınmaz.
            let countryNames = Set(Country.all.flatMap { [Country.fold($0.name), Country.fold($0.title)] })
            self.cities = Array(results
                .filter { !$0.title.contains(where: \.isNumber) && !countryNames.contains(Country.fold($0.title)) }
                .prefix(8))
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.isSearching = false }
    }

    /// Seçilen sonucun konumu, ülkesi ve İngilizce Wikipedia başlığı.
    static func resolve(_ completion: MKLocalSearchCompletion) async -> CityChoice? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let placemark = item.placemark
        let name = completion.title.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? completion.title
        let english = await DiscoverService.shared.englishTitle(for: name)
        return CityChoice(name: name, countryCode: placemark.isoCountryCode,
                          latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude,
                          englishTitle: english)
    }
}

/// Gezide iki şehir arası yol: araba mesafesi ve süresi (Apple Haritalar,
/// ücretsiz). Yol yoksa (deniz aşırı) kuş uçuşu mesafe; uçuş eklenebilir.
@MainActor
enum TravelLegs {
    struct Leg: Equatable {
        var meters: Double
        /// Araba süresi; nil ise yol bulunamadı.
        var seconds: Double?
    }

    private static var cache: [String: Leg] = [:]

    static func leg(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Leg {
        let key = "\(a.latitude),\(a.longitude)>\(b.latitude),\(b.longitude)"
        if let cached = cache[key] { return cached }
        let straight = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        var leg = Leg(meters: straight, seconds: nil)
        if straight < 2_500_000 {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            request.transportType = .automobile
            if let route = try? await MKDirections(request: request).calculate().routes.first {
                leg = Leg(meters: route.distance, seconds: route.expectedTravelTime)
            }
        }
        cache[key] = leg
        return leg
    }

    /// "446 km · 4 sa 43 dk"
    static func text(_ leg: Leg) -> String {
        let km = Int((leg.meters / 1000).rounded())
        guard let seconds = leg.seconds else { return String(localized: "\(km) km kuş uçuşu") }
        let minutes = Int((seconds / 60).rounded())
        let time = minutes >= 60
            ? String(localized: "\(minutes / 60) sa \(minutes % 60) dk")
            : String(localized: "\(minutes) dk")
        return "\(km) km · \(time)"
    }
}

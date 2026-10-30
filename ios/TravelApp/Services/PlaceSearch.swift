import MapKit
import SwiftUI

/// Apple Haritalar'da yer arama: ücretsiz, anahtar istemez. Aktarılan
/// yerlerin türü bunu kullanır ("Yer ekle" araması Google'da).
enum PlaceSearch {
    /// Aktarılan bir yerin Apple Haritalar'daki türü: aynı adla aranır,
    /// 300 m içindeki ilk sonuç alınır. Sınıra takılınca `throttled` döner.
    enum Lookup {
        case found(PlaceCategory?)
        case throttled
    }

    static func category(of name: String, near coordinate: CLLocationCoordinate2D) async -> Lookup {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_000, longitudinalMeters: 1_000)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            // Sonuçlar ada uygunluğa göre sıralı gelir; yakındaki ilk sonuç alınır.
            let items = try await MKLocalSearch(request: request).start().mapItems
            let match = items.first { ($0.placemark.location?.distance(from: location) ?? .infinity) < 300 }
            return .found(match.flatMap { PlaceCategory(apple: $0.pointOfInterestCategory) })
        } catch let error as MKError where error.code == .loadingThrottled {
            return .throttled
        } catch {
            return .found(nil)
        }
    }
}

extension PlaceCategory {
    /// Apple Haritalar türünden bizim türümüze. Apple'da tapınak türü
    /// olmadığı için tapınak addan bulunur; bilinmeyen türde nil.
    init?(apple category: MKPointOfInterestCategory?) {
        guard let category else { return nil }
        switch category {
        case .museum: self = .museum
        case .restaurant, .bakery, .foodMarket: self = .food
        case .cafe: self = .cafe
        case .nightlife, .brewery, .winery: self = .bar
        case .hotel: self = .hotel
        case .store: self = .shopping
        case .park, .nationalPark, .beach, .campground: self = .park
        case .aquarium, .zoo, .amusementPark, .theater, .stadium, .marina: self = .sight
        case .airport, .publicTransport, .carRental, .parking, .evCharger, .gasStation, .bank, .atm,
             .hospital, .pharmacy, .police, .postOffice, .fireStation, .restroom, .laundry,
             .school, .university, .library, .fitnessCenter:
            self = .other
        default: return nil
        }
    }

    /// Apple Haritalar yerinin türü. Apple'ın türü belirginse o, değilse
    /// (park, görülecek yer, bilinmiyor) addan tahmin: Meiji Jingu
    /// parkta olsa da tapınaktır.
    init(_ item: MKMapItem, fallback: PlaceCategory = .sight) {
        self.init(apple: item.pointOfInterestCategory, name: item.name ?? "", fallback: fallback)
    }

    init(apple category: MKPointOfInterestCategory?, name: String, fallback: PlaceCategory = .sight) {
        let fromApple = PlaceCategory(apple: category)
        if let fromApple, ![.park, .sight, .other].contains(fromApple) {
            self = fromApple
        } else {
            self = PlaceCategory.guess(name: name) ?? fromApple ?? fallback
        }
    }
}

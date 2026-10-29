import CoreLocation
import Foundation

/// Google Places (New): yerin puanı, yorumları, fotoğrafları, açılış
/// saatleri, telefonu ve web sitesi; "Yer ekle" araması. Google'ın kuralı
/// gereği bu bilgiler yalnızca Google haritasıyla birlikte gösterilir ve
/// telefonda saklanmaz (yalnızca yerin Google kimliği saklanır); uygulama
/// açıkken bellekte tutulur, aynı yer tekrar açılınca yeni istek gitmez.
///
/// Ücretsiz aylık kotalar (Google Cloud'da günlük üst sınırlarla
/// korunur): yer bilgisi 1.000, fotoğraf 1.000, arama 5.000; kimlik bulma
/// sınırsız.
@MainActor
final class GooglePlaces {
    static let shared = GooglePlaces()

    struct Details: Equatable {
        var id: String
        var name: String
        var address: String?
        var latitude: Double
        var longitude: Double
        var types: [String]
        var primaryType: String?
        /// Google'ın tür adı uygulamanın dilinde ("Ramen restoranı").
        var typeName: String?
        var rating: Double?
        var ratingCount: Int?
        /// 0 (ücretsiz) – 4 (çok pahalı).
        var priceLevel: Int?
        var openNow: Bool?
        /// Haftanın günleri: "Pazartesi: 09:00–17:00".
        var hours: [String]
        var phone: String?
        var website: URL?
        var mapsURL: URL?
        var summary: String?
        var reviews: [Review]
        var photos: [Photo]

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        var category: PlaceCategory { PlaceCategory(googleTypes: types, primary: primaryType, name: name) }
    }

    struct Review: Identifiable, Equatable {
        var id: String
        var author: String
        var authorURL: URL?
        var authorPhoto: URL?
        var rating: Int
        /// "2 hafta önce" (Google, uygulamanın dilinde).
        var when: String
        var text: String
    }

    struct Photo: Identifiable, Equatable {
        /// Google'daki adı ("places/…/photos/…"); resmin adresi bundan istenir.
        var id: String
        var author: String?
        var authorURL: URL?
    }

    struct SearchResult: Identifiable, Equatable {
        var id: String
        var name: String
        var address: String
        var latitude: Double
        var longitude: Double
        var types: [String]
        var primaryType: String?

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        var category: PlaceCategory { PlaceCategory(googleTypes: types, primary: primaryType, name: name) }
    }

    private var cachedDetails: [String: Details] = [:]
    private var photoURLs: [String: URL] = [:]
    private var placeIDs: [String: String] = [:]

    private static let base = "https://places.googleapis.com/v1/"

    /// Ekran görüntüsü açılışları (yalnızca geliştirme sürümü) Google'ın
    /// ücretsiz kotasını boşa harcamasın: yer bilgisi ve fotoğraf yalnızca
    /// Google'ı gösteren ekranlarda istenir.
    private static var skipsForScreenshot: Bool {
        #if DEBUG
        if let screen = UserDefaults.standard.string(forKey: "screen") {
            return !["sheet", "googlePlace", "googleTall"].contains(screen)
        }
        #endif
        return false
    }

    /// Yerin bütün bilgileri (puan, yorumlar, fotoğraflar, saatler...).
    func details(id: String) async -> Details? {
        let key = "\(GoogleAPI.language)|\(id)"
        if let cached = cachedDetails[key] { return cached }
        guard !Self.skipsForScreenshot else { return nil }
        var components = URLComponents(string: Self.base + "places/" + id)!
        components.queryItems = [.init(name: "languageCode", value: GoogleAPI.language)]
        let fields = "id,displayName,formattedAddress,location,types,primaryType,primaryTypeDisplayName,rating,"
            + "userRatingCount,priceLevel,currentOpeningHours,regularOpeningHours,nationalPhoneNumber,"
            + "internationalPhoneNumber,websiteUri,googleMapsUri,editorialSummary,reviews,photos"
        guard let url = components.url,
              let request = try? GoogleAPI.request(url, fields: fields),
              let raw = try? await GoogleAPI.fetch(RawPlace.self, request),
              let result = raw.details else { return nil }
        cachedDetails[key] = result
        return result
    }

    /// Fotoğrafın resim adresi (her fotoğraf bir istek; kısa süre geçerli).
    func photoURL(_ photo: Photo, maxWidth: Int = 900) async -> URL? {
        if let cached = photoURLs[photo.id] { return cached }
        guard !Self.skipsForScreenshot else { return nil }
        guard let url = URL(string: Self.base + photo.id + "/media?maxWidthPx=\(maxWidth)&skipHttpRedirect=true"),
              let request = try? GoogleAPI.request(url) else { return nil }
        struct Media: Decodable { var photoUri: String? }
        guard let media = try? await GoogleAPI.fetch(Media.self, request),
              let found = media.photoUri.flatMap(URL.init(string:)) else { return nil }
        photoURLs[photo.id] = found
        return found
    }

    /// "Yer ekle" araması: yazılan ad ya da tür ("ramen", "Park Hyatt"),
    /// verilen noktanın çevresi öncelikli.
    func search(_ text: String, near center: CLLocationCoordinate2D?) async -> [SearchResult] {
        var body: [String: Any] = ["textQuery": text, "languageCode": GoogleAPI.language, "pageSize": 15]
        if let center { body["locationBias"] = Self.circle(center, radius: 30_000) }
        let fields = "places.id,places.displayName,places.formattedAddress,places.shortFormattedAddress,"
            + "places.location,places.types,places.primaryType"
        guard let url = URL(string: Self.base + "places:searchText"),
              let request = try? GoogleAPI.request(url, fields: fields, body: body),
              let response = try? await GoogleAPI.fetch(SearchResponse.self, request) else { return [] }
        return (response.places ?? []).compactMap(\.searchResult)
    }

    /// Kayıtlı bir yerin Google kimliği: aynı adla, yakınında aranır
    /// (yalnızca kimlik istenir; bu arama ücretsiz ve sınırsız).
    func findID(name: String, near coordinate: CLLocationCoordinate2D) async -> String? {
        let key = "\(name)|\((coordinate.latitude * 1000).rounded())|\((coordinate.longitude * 1000).rounded())"
        if let cached = placeIDs[key] { return cached }
        let body: [String: Any] = ["textQuery": name, "pageSize": 1, "locationBias": Self.circle(coordinate, radius: 400)]
        guard let url = URL(string: Self.base + "places:searchText"),
              let request = try? GoogleAPI.request(url, fields: "places.id", body: body),
              let response = try? await GoogleAPI.fetch(SearchResponse.self, request),
              let id = response.places?.first?.id else { return nil }
        placeIDs[key] = id
        return id
    }

    private static func circle(_ center: CLLocationCoordinate2D, radius: Double) -> [String: Any] {
        ["circle": ["center": ["latitude": center.latitude, "longitude": center.longitude], "radius": radius]]
    }

    // MARK: - Google'ın cevabı

    private struct SearchResponse: Decodable {
        var places: [RawPlace]?
    }

    private struct LocalizedText: Decodable {
        var text: String?
    }

    private struct LatLng: Decodable {
        var latitude: Double
        var longitude: Double
    }

    private struct Attribution: Decodable {
        var displayName: String?
        var uri: String?
        var photoUri: String?
    }

    private struct RawReview: Decodable {
        var name: String?
        var relativePublishTimeDescription: String?
        var rating: Double?
        var text: LocalizedText?
        var originalText: LocalizedText?
        var authorAttribution: Attribution?
    }

    private struct RawPhoto: Decodable {
        var name: String
        var authorAttributions: [Attribution]?
    }

    private struct Hours: Decodable {
        var openNow: Bool?
        var weekdayDescriptions: [String]?
    }

    private struct RawPlace: Decodable {
        var id: String?
        var displayName: LocalizedText?
        var formattedAddress: String?
        var shortFormattedAddress: String?
        var location: LatLng?
        var types: [String]?
        var primaryType: String?
        var primaryTypeDisplayName: LocalizedText?
        var rating: Double?
        var userRatingCount: Int?
        var priceLevel: String?
        var currentOpeningHours: Hours?
        var regularOpeningHours: Hours?
        var nationalPhoneNumber: String?
        var internationalPhoneNumber: String?
        var websiteUri: String?
        var googleMapsUri: String?
        var editorialSummary: LocalizedText?
        var reviews: [RawReview]?
        var photos: [RawPhoto]?

        var details: Details? {
            guard let id, let location else { return nil }
            let reviews = (self.reviews ?? []).enumerated().compactMap { index, review -> Review? in
                guard let text = review.text?.text ?? review.originalText?.text, !text.isEmpty else { return nil }
                return Review(id: review.name ?? "\(index)",
                              author: review.authorAttribution?.displayName ?? "Google",
                              authorURL: review.authorAttribution?.uri.flatMap(URL.init(string:)),
                              authorPhoto: review.authorAttribution?.photoUri.flatMap(URL.init(string:)),
                              rating: Int((review.rating ?? 0).rounded()),
                              when: review.relativePublishTimeDescription ?? "",
                              text: text)
            }
            let photos = (self.photos ?? []).map { photo in
                Photo(id: photo.name, author: photo.authorAttributions?.first?.displayName,
                      authorURL: photo.authorAttributions?.first?.uri.flatMap(URL.init(string:)))
            }
            let hours = currentOpeningHours ?? regularOpeningHours
            return Details(id: id, name: displayName?.text ?? "", address: formattedAddress,
                           latitude: location.latitude, longitude: location.longitude,
                           types: types ?? [], primaryType: primaryType, typeName: primaryTypeDisplayName?.text,
                           rating: rating, ratingCount: userRatingCount, priceLevel: Self.price(priceLevel),
                           openNow: hours?.openNow, hours: hours?.weekdayDescriptions ?? [],
                           phone: nationalPhoneNumber ?? internationalPhoneNumber,
                           website: websiteUri.flatMap(URL.init(string:)),
                           mapsURL: googleMapsUri.flatMap(URL.init(string:)),
                           summary: editorialSummary?.text, reviews: reviews, photos: photos)
        }

        var searchResult: SearchResult? {
            guard let id, let location, let name = displayName?.text else { return nil }
            return SearchResult(id: id, name: name, address: shortFormattedAddress ?? formattedAddress ?? "",
                                latitude: location.latitude, longitude: location.longitude,
                                types: types ?? [], primaryType: primaryType)
        }

        private static func price(_ level: String?) -> Int? {
            switch level {
            case "PRICE_LEVEL_FREE": 0
            case "PRICE_LEVEL_INEXPENSIVE": 1
            case "PRICE_LEVEL_MODERATE": 2
            case "PRICE_LEVEL_EXPENSIVE": 3
            case "PRICE_LEVEL_VERY_EXPENSIVE": 4
            default: nil
            }
        }
    }
}

extension PlaceCategory {
    /// Google'ın yer türünden bizim türümüze ("ramen_restaurant" yemek,
    /// "buddhist_temple" tapınak). Türü belirsizse (park, görülecek yer)
    /// addan tahmin edilir: Meiji Jingu parkta olsa da tapınaktır.
    init(googleTypes types: [String], primary: String?, name: String) {
        let ordered = (primary.map { [$0] } ?? []) + types
        let fromGoogle = ordered.lazy.compactMap(PlaceCategory.init(googleType:)).first
        if let fromGoogle, ![.park, .sight, .other].contains(fromGoogle) {
            self = fromGoogle
        } else {
            self = PlaceCategory.guess(name: name) ?? fromGoogle ?? .sight
        }
    }

    init?(googleType type: String) {
        switch type {
        case "cafe", "coffee_shop", "tea_house", "cat_cafe", "dog_cafe", "internet_cafe":
            self = .cafe
        case "bar", "pub", "wine_bar", "night_club", "cocktail_bar", "lounge_bar", "brewery", "brewpub", "sports_bar":
            self = .bar
        case "museum", "art_gallery", "art_museum", "history_museum":
            self = .museum
        case "church", "hindu_temple", "mosque", "synagogue", "place_of_worship", "buddhist_temple",
             "shinto_shrine", "cathedral":
            self = .temple
        case "observation_deck":
            self = .viewpoint
        case "lodging", "hotel", "hostel", "motel", "bed_and_breakfast", "resort_hotel", "inn",
             "guest_house", "japanese_inn", "budget_japanese_inn", "extended_stay_hotel", "campground":
            self = .hotel
        case "park", "national_park", "state_park", "garden", "botanical_garden", "beach", "hiking_area",
             "city_park", "japanese_garden":
            self = .park
        case "shopping_mall", "store", "market", "department_store", "clothing_store", "gift_shop",
             "book_store", "supermarket", "flea_market", "farmers_market", "shopping_street":
            self = .shopping
        case "tourist_attraction", "historical_landmark", "historical_place", "monument", "cultural_landmark",
             "amusement_park", "aquarium", "zoo", "plaza", "castle", "landmark", "sculpture", "fountain":
            self = .sight
        case "restaurant", "food", "meal_takeaway", "meal_delivery", "bakery", "food_court", "deli",
             "dessert_shop", "ice_cream_shop", "sandwich_shop", "confectionery", "cafeteria", "diner", "bistro":
            self = .food
        default:
            if type.hasSuffix("_restaurant") {
                self = .food
            } else if type.hasSuffix("_museum") {
                self = .museum
            } else if type.hasSuffix("_store") {
                self = .shopping
            } else {
                return nil
            }
        }
    }
}

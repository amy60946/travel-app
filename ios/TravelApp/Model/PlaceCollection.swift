import CoreLocation
import Foundation

/// Koleksiyon (Polarsteps "Collections" gibi): kullanıcının adlandırdığı
/// arşiv; içinde ülkeler, şehirler ve yerler. Keşfet → Koleksiyonlar'da
/// görünür; kaydet düğmesiyle (yer işareti) eklenir.
struct PlaceCollection: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String
    /// `PlaceCollection.colors` içindeki sıra.
    var color: Int
    var items: [CollectionItem] = []

    /// Yeni koleksiyon penceresindeki seçenekler.
    static let emojis = ["🌴", "🏛️", "🍜", "☕️", "🏔️", "🌊", "🏙️", "❤️"]
    static let colors: [UInt32] = [0x8EC5F7, 0x7EE0B5, 0xF4B183, 0xE3B5C8, 0x4A4540, 0xD9D6D0]

    var destinations: [CollectionItem] { items.filter { $0.kind != .place } }
    var spots: [CollectionItem] { items.filter { $0.kind == .place } }
}

/// Koleksiyondaki bir şey: ülke, şehir ya da kayıtlı yer.
struct CollectionItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case country, city, place
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var countryCode: String?
    var latitude: Double?
    var longitude: Double?
    /// İngilizce Wikipedia / Wikivoyage başlığı (fotoğraf ve rehber için).
    var englishTitle: String?
    /// Yerse, Kayıtlarım'daki kaydı.
    var placeID: UUID?
    var category: PlaceCategory?

    /// Aynı şey bir koleksiyona iki kez eklenmesin diye.
    var key: String {
        switch kind {
        case .country: "country|\(countryCode ?? name)"
        case .city: "city|\(englishTitle ?? name)"
        case .place: "place|\(placeID?.uuidString ?? name)"
        }
    }

    /// Görünen ad: ülke adı uygulamanın dilinde.
    var displayName: String {
        if kind == .country, let code = countryCode, let country = Country.find(code) { return country.name }
        return name
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func country(_ country: Country) -> CollectionItem {
        CollectionItem(kind: .country, name: country.name, countryCode: country.code, englishTitle: country.title)
    }

    static func city(_ city: CityChoice) -> CollectionItem {
        CollectionItem(kind: .city, name: city.name, countryCode: city.countryCode,
                       latitude: city.latitude, longitude: city.longitude, englishTitle: city.englishTitle ?? city.name)
    }

    static func place(_ place: Place) -> CollectionItem {
        CollectionItem(kind: .place, name: place.name, latitude: place.latitude, longitude: place.longitude,
                       englishTitle: place.wikipediaTitle, placeID: place.id, category: place.category)
    }
}

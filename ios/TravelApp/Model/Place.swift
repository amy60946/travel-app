import CoreLocation
import Foundation

enum PlaceSource: String, Codable, CaseIterable, Identifiable {
    case instagram, tiktok, googleMaps, manual, photo, search, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .googleMaps: "Google Maps"
        case .manual: String(localized: "Kendi yerin")
        case .photo: String(localized: "Fotoğraf")
        case .search: String(localized: "Arama")
        case .text: String(localized: "Yazıdan")
        }
    }

    /// "Instagram'da kaydettin" gibi, yalnızca sosyal kaynaklar için.
    var savedNote: String? {
        switch self {
        case .instagram: String(localized: "Instagram'da kaydettin")
        case .tiktok: String(localized: "TikTok'ta kaydettin")
        case .googleMaps: String(localized: "Google Maps'te kaydettin")
        default: nil
        }
    }
}

enum PlaceCategory: String, Codable, CaseIterable, Identifiable {
    case sight, temple, museum, food, cafe, shopping, park, viewpoint, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sight: String(localized: "Görülecek yer")
        case .temple: String(localized: "Tapınak")
        case .museum: String(localized: "Müze")
        case .food: String(localized: "Yemek")
        case .cafe: String(localized: "Kafe")
        case .shopping: String(localized: "Alışveriş")
        case .park: String(localized: "Park")
        case .viewpoint: String(localized: "Manzara")
        case .other: String(localized: "Diğer")
        }
    }

    var symbol: String {
        switch self {
        case .sight: "star"
        case .temple: "building.columns"
        case .museum: "photo.artframe"
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer"
        case .shopping: "bag"
        case .park: "leaf"
        case .viewpoint: "binoculars"
        case .other: "mappin"
        }
    }

    /// Yer başına ortalama süre (dakika), rota tahmini için.
    var averageMinutes: Int {
        switch self {
        case .museum: 90
        case .temple, .park: 60
        case .food: 60
        case .cafe: 40
        case .shopping: 45
        case .viewpoint: 45
        case .sight, .other: 30
        }
    }
}

struct Place: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var city: String
    var latitude: Double
    var longitude: Double
    var category: PlaceCategory
    var source: PlaceSource
    /// Yer kendiliğinden bulundu ama emin değiliz ("Tahmini" etiketi).
    var isEstimated = false
    var note = ""
    /// İngilizce Wikipedia başlığı; açıklama ve fotoğraf buradan gelir.
    var wikipediaTitle: String?
    var addedAt = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// Bir şehirdeki gezi planı. Rota planlayıcı günleri buradan üretir.
struct Trip: Codable, Hashable {
    var city: String
    var days: Int
    var pace: Pace
    /// Rotaya eklenmiş yerler, öncelik sırasıyla.
    var placeIDs: [UUID]
}

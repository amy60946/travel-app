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
    case sight, temple, museum, food, cafe, shopping, park, viewpoint, bar, hotel, other

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
        case .bar: String(localized: "Bar")
        case .hotel: String(localized: "Konaklama")
        case .other: String(localized: "Diğer")
        }
    }

    var symbol: String {
        switch self {
        case .sight: "star.fill"
        case .temple: "building.columns.fill"
        case .museum: "photo.artframe"
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .shopping: "bag.fill"
        case .park: "leaf.fill"
        case .viewpoint: "binoculars.fill"
        case .bar: "wineglass.fill"
        case .hotel: "bed.double.fill"
        case .other: "mappin"
        }
    }

    /// Yer başına ortalama süre (dakika), rota tahmini için.
    var averageMinutes: Int {
        switch self {
        case .museum: 90
        case .temple, .park: 60
        case .food, .bar: 60
        case .cafe: 40
        case .shopping: 45
        case .viewpoint: 45
        case .hotel: 15
        case .sight, .other: 30
        }
    }

    /// Addan tür tahmini: "Sensō-ji" tapınak, "Blue Bottle Coffee" kafe.
    /// Veri dosyasından gelen yerlerde ve Apple Haritalar türü
    /// bilmediğinde kullanılır. Bulamazsa nil.
    static func guess(name: String) -> PlaceCategory? {
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return keywords.first { _, keys in
            keys.contains { key in
                if key.hasSuffix("*") {
                    let stem = key.dropLast()
                    return words.contains { $0.hasPrefix(stem) }
                }
                // Birden çok kelime ya da Japonca: metnin içinde aranır.
                if key.contains(" ") || !key.allSatisfy(\.isASCII) { return folded.contains(key) }
                return words.contains(key)
            }
        }?.category
    }

    /// Sıra önemli: "Park Hotel" konaklama, "Temple Bar" bar, "Ramen
    /// Museum" yemek sayılır. "*" ile biten anahtar kelimenin başıdır.
    private static let keywords: [(category: PlaceCategory, keys: [String])] = [
        (.hotel, ["hotel*", "otel*", "hostel*", "ryokan", "inn", "resort", "pansiyon", "motel",
                  "hyatt", "hilton", "marriott", "sheraton", "westin", "airbnb", "旅館", "ホテル", "ホステル"]),
        (.cafe, ["cafe", "caffe", "kafe*", "kahve*", "coffee", "espresso", "roaster*", "roastery",
                 "kissaten", "teahouse", "matcha", "cay", "starbucks", "カフェ", "珈琲", "喫茶", "コーヒー"]),
        (.bar, ["bar", "bars", "pub", "brewery", "brewing", "taproom", "cocktail*", "speakeasy",
                "meyhane*", "biergarten", "バー"]),
        (.food, ["restaurant*", "restoran*", "lokanta*", "ramen", "sushi", "izakaya", "yakitori",
                 "yakiniku", "udon", "soba", "tempura", "tonkatsu", "okonomiyaki", "takoyaki", "gyoza",
                 "kebap*", "kebab*", "doner", "pizza*", "pizzeria", "burger*", "bistro", "brasserie",
                 "trattoria", "osteria", "diner", "eatery", "kitchen", "grill", "steakhouse", "bakery",
                 "firin*", "pastane*", "patisserie", "boulangerie", "noodle*", "curry", "food",
                 "ice cream", "dondurma*", "baklava*", "ラーメン", "寿司", "鮨", "食堂", "居酒屋",
                 "うどん", "焼肉", "焼鳥", "レストラン", "ベーカリー"]),
        (.museum, ["museum*", "muze*", "museo", "musee", "museu*", "gallery", "galeri*",
                   "kunsthalle", "exhibition", "sergi*", "teamlab", "美術館", "博物館",
                   "ミュージアム", "記念館", "資料館"]),
        (.temple, ["temple", "shrine", "jinja", "jingu", "taisha", "tera", "dera", "ji",
                   "mosque", "cami", "camii", "camisi", "church", "kilise*", "cathedral",
                   "katedral*", "basilica", "bazilika*", "chapel", "synagogue", "sinagog*",
                   "pagoda", "monastery", "manastir*", "tapinak", "tapinagi", "寺", "神社",
                   "神宮", "大社"]),
        (.viewpoint, ["observatory", "observation", "viewpoint", "lookout", "overlook", "tower",
                      "kule*", "skytree", "sky", "seyir*", "panorama*", "展望", "タワー"]),
        (.park, ["park", "parks", "parki", "garden*", "bahce*", "gyoen", "koen", "kouen", "teien",
                 "beach", "plaj*", "forest", "botanical", "botanik", "公園", "庭園", "御苑"]),
        (.shopping, ["mall", "market", "marketplace", "bazaar", "pazar*", "carsi*", "arcade",
                     "outlet*", "shop", "shops", "store", "boutique", "butik*", "magaza*",
                     "shotengai", "department store", "商店街", "市場", "百貨店"]),
    ]
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
    /// Yerin geldiği gönderi ya da harita linki (Instagram, TikTok, Google Maps).
    var sourceURL: URL?
    /// Yerin Google kimliği: puan, yorumlar ve fotoğraflar Google'dan bununla
    /// istenir (Google'ın kuralına göre saklanabilen tek Google bilgisi).
    var googlePlaceID: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// Gezideki bir şehrin planı (günler ve yerler). Her gezinin şehri kendi
/// planını tutar: aynı şehir iki gezide olsa da planları ayrıdır.
struct Trip: Codable, Hashable {
    var city: String
    var days: Int
    /// Tempo seçimi şimdilik arayüzde yok (2026-10-29); eski kayıtlar için durur.
    var pace: Pace
    /// Rotaya eklenmiş yerler; elle sıralanan günlerde bu sırayla görünür.
    var placeIDs: [UUID]
    /// Her yerin günü (0'dan), kullanıcı seçer. Eski kayıtlarda yoksa
    /// açılışta bir kez doldurulur.
    var dayOf: [UUID: Int]?
    /// Planın ait olduğu gezi şehri (`Destination.id`). Eski kayıtlarda
    /// (planlar şehre bağlıyken) yok; açılışta bir kez bağlanır.
    var stopID: UUID?
    /// Kullanıcının basılı tutup sürükleyerek sıraladığı günler; öteki
    /// günler yürüme yoluna göre kendiliğinden sıralanır.
    var manualDays: Set<Int>?

    init(city: String, days: Int, pace: Pace = .normal, placeIDs: [UUID] = [], dayOf: [UUID: Int]? = [:],
         stopID: UUID? = nil) {
        self.city = city
        self.days = days
        self.pace = pace
        self.placeIDs = placeIDs
        self.dayOf = dayOf
        self.stopID = stopID
    }
}

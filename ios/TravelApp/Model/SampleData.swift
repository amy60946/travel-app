import Foundation

/// İlk açılışta gösterilen örnek kayıtlar. Gerçek kayıt aktarımı
/// (paylaşma menüsü, veri dosyası) gelince bunların yerini alacak.
enum SampleData {
    static let places: [Place] = [
        p("Sensō-ji", "Tokyo", 35.7148, 139.7967, .temple, .instagram, "Sensō-ji"),
        p("Tokyo Skytree", "Tokyo", 35.7101, 139.8107, .viewpoint, .tiktok, "Tokyo Skytree"),
        p("Ueno Parkı", "Tokyo", 35.7156, 139.7745, .park, .googleMaps, "Ueno Park"),
        p("Tokyo Ulusal Müzesi", "Tokyo", 35.7188, 139.7765, .museum, .googleMaps, "Tokyo National Museum"),
        p("Yanaka Ginza", "Tokyo", 35.7275, 139.7660, .shopping, .instagram, "Yanaka, Tokyo"),
        p("Meiji Tapınağı", "Tokyo", 35.6764, 139.6993, .temple, .instagram, "Meiji Shrine"),
        p("Takeshita Sokağı", "Tokyo", 35.6715, 139.7031, .shopping, .tiktok, "Takeshita Street"),
        p("Shibuya Kavşağı", "Tokyo", 35.6595, 139.7005, .sight, .tiktok, "Shibuya Crossing"),
        p("Shinjuku Gyoen", "Tokyo", 35.6852, 139.7101, .park, .instagram, "Shinjuku Gyo-en"),
        p("Omoide Yokochō", "Tokyo", 35.6933, 139.6995, .food, .tiktok, "Omoide Yokochō"),
        p("Tsukiji Dış Pazarı", "Tokyo", 35.6655, 139.7707, .food, .googleMaps, "Tsukiji fish market"),
        p("Tokyo Kulesi", "Tokyo", 35.6586, 139.7454, .viewpoint, .googleMaps, "Tokyo Tower"),
        p("İmparatorluk Sarayı", "Tokyo", 35.6852, 139.7528, .park, .googleMaps, "Tokyo Imperial Palace"),
        p("Gōtoku-ji", "Tokyo", 35.6489, 139.6474, .temple, .instagram, "Gōtoku-ji", estimated: true),
        p("Galata Kulesi", "İstanbul", 41.0256, 28.9741, .viewpoint, .instagram, "Galata Tower"),
        p("Süleymaniye Camii", "İstanbul", 41.0162, 28.9639, .temple, .googleMaps, "Süleymaniye Mosque"),
    ]

    static func trips(for places: [Place]) -> [Trip] {
        // Günler (dayOf) boş bırakılır: açılışta yerler bir kez günlere dağıtılır.
        [Trip(city: "Tokyo", days: 3, pace: .normal,
              placeIDs: places.filter { $0.city == "Tokyo" }.map(\.id), dayOf: nil)]
    }

    private static func p(
        _ name: String, _ city: String, _ lat: Double, _ lon: Double,
        _ category: PlaceCategory, _ source: PlaceSource, _ wiki: String,
        estimated: Bool = false
    ) -> Place {
        Place(name: name, city: city, latitude: lat, longitude: lon,
              category: category, source: source, isEstimated: estimated,
              wikipediaTitle: wiki)
    }
}

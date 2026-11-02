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

#if DEBUG
/// Ekran görüntüleri için örnek paylaşılan geziler (internetsiz).
extension SampleData {
    static let demoUserID = UUID(uuidString: "0B6E1F3C-6A2D-4C34-9E43-9D2B2C0F7A11")!

    static func sharedTrips(matching query: String = "", owner: UUID? = nil) -> [SharedTrip] {
        let words = TripSharing.fold(query).split(separator: " ").map(String.init)
        return demoTrips.filter { trip in
            let text = TripSharing.searchText(title: trip.title, cities: trip.cities, countryCodes: trip.countryCodes)
            return words.allSatisfy { text.contains($0) } && (owner == nil || trip.owner == owner)
        }
    }

    private static let demoTrips: [SharedTrip] = [
        trip("6C1D7A55-0F4B-4C1E-9B7B-2C9E8E1A0001", owner: "7A0E2B11-3C4D-4E5F-8A9B-0C1D2E3F4A01",
             author: .init(name: "Elif", emoji: "🌸"), title: "Japonya'da 10 gün", codes: ["JP"], stops: [
                 stop("Tokyo", "JP", 35.6762, 139.6503, "Tokyo", days: 4, spots: [
                     spot("Sensō-ji", .temple, 35.7148, 139.7967, 0, "Sensō-ji"),
                     spot("Tokyo Skytree", .viewpoint, 35.7101, 139.8107, 0, "Tokyo Skytree"),
                     spot("Tsukiji Dış Pazarı", .food, 35.6655, 139.7707, 1, "Tsukiji fish market"),
                     spot("teamLab Planets", .museum, 35.6491, 139.7898, 1, "TeamLab"),
                     spot("Meiji Tapınağı", .temple, 35.6764, 139.6993, 2, "Meiji Shrine"),
                     spot("Shibuya Kavşağı", .sight, 35.6595, 139.7005, 2, "Shibuya Crossing"),
                 ]),
                 stop("Kyoto", "JP", 35.0116, 135.7681, "Kyoto", days: 3, spots: [
                     spot("Fushimi Inari Taisha", .temple, 34.9671, 135.7727, 0, "Fushimi Inari-taisha"),
                     spot("Kiyomizu-dera", .temple, 34.9949, 135.7850, 0, "Kiyomizu-dera"),
                     spot("Nishiki Pazarı", .food, 35.0050, 135.7650, 1, "Nishiki Market"),
                     spot("Arashiyama Bambu Ormanı", .park, 35.0170, 135.6713, 2, "Sagano Bamboo Forest"),
                     spot("Kinkaku-ji", .temple, 35.0394, 135.7292, 2, "Kinkaku-ji"),
                 ]),
                 stop("Osaka", "JP", 34.6937, 135.5023, "Osaka", days: 3, travelMode: "train", spots: [
                     spot("Osaka Kalesi", .sight, 34.6873, 135.5262, 0, "Osaka Castle"),
                     spot("Dōtonbori", .food, 34.6687, 135.5013, 0, "Dōtonbori"),
                     spot("Shinsekai", .shopping, 34.6525, 135.5063, 1, "Shinsekai"),
                 ]),
             ]),
        trip("6C1D7A55-0F4B-4C1E-9B7B-2C9E8E1A0002", owner: "7A0E2B11-3C4D-4E5F-8A9B-0C1D2E3F4A02",
             author: .init(name: "Mert", emoji: "🍝"), title: "İtalya klasikleri", codes: ["IT"], stops: [
                 stop("Roma", "IT", 41.9028, 12.4964, "Rome", days: 3, spots: [
                     spot("Kolezyum", .sight, 41.8902, 12.4922, 0, "Colosseum"),
                     spot("Pantheon", .sight, 41.8986, 12.4769, 0, "Pantheon, Rome"),
                     spot("Aşk Çeşmesi", .sight, 41.9009, 12.4833, 1, "Trevi Fountain"),
                     spot("Vatikan Müzeleri", .museum, 41.9065, 12.4536, 2, "Vatican Museums"),
                 ]),
                 stop("Floransa", "IT", 43.7696, 11.2558, "Florence", days: 2, travelMode: "train", spots: [
                     spot("Uffizi Galerisi", .museum, 43.7678, 11.2553, 0, "Uffizi"),
                     spot("Floransa Katedrali", .temple, 43.7731, 11.2560, 0, "Florence Cathedral"),
                     spot("Piazzale Michelangelo", .viewpoint, 43.7629, 11.2650, 1, "Piazzale Michelangelo"),
                 ]),
                 stop("Venedik", "IT", 45.4408, 12.3155, "Venice", days: 2, travelMode: "train", spots: [
                     spot("San Marco Bazilikası", .temple, 45.4345, 12.3397, 0, "St Mark's Basilica"),
                     spot("Rialto Köprüsü", .sight, 45.4380, 12.3359, 0, "Rialto Bridge"),
                     spot("Burano", .sight, 45.4853, 12.4167, 1, "Burano"),
                 ]),
             ]),
        trip("6C1D7A55-0F4B-4C1E-9B7B-2C9E8E1A0003", owner: demoUserID.uuidString,
             author: .init(name: "Oguz", emoji: "🧭"), title: "Kapadokya hafta sonu", codes: ["TR"], stops: [
                 stop("Kapadokya", "TR", 38.6431, 34.8289, "Cappadocia", days: 2, spots: [
                     spot("Göreme Açık Hava Müzesi", .museum, 38.6400, 34.8456, 0, "Göreme Open Air Museum"),
                     spot("Uçhisar Kalesi", .viewpoint, 38.6305, 34.8040, 0, "Uçhisar"),
                     spot("Paşabağ", .sight, 38.6719, 34.8530, 1, "Paşabağ"),
                     spot("Avanos", .shopping, 38.7150, 34.8470, 1, "Avanos"),
                 ]),
             ]),
    ]

    private static func trip(_ id: String, owner: String, author: SharedTrip.Author, title: String, codes: [String],
                             stops: [SharedTrip.Payload.Stop]) -> SharedTrip {
        SharedTrip(id: UUID(uuidString: id)!, owner: UUID(uuidString: owner)!, localID: UUID(uuidString: id)!,
                   title: title, cities: stops.map(\.city), countryCodes: codes,
                   days: stops.reduce(0) { $0 + $1.days }, placeCount: stops.reduce(0) { $0 + $1.places.count },
                   coverTitle: stops.first?.englishTitle, data: SharedTrip.Payload(stops: stops), author: author)
    }

    private static func stop(_ city: String, _ code: String, _ lat: Double, _ lon: Double, _ title: String,
                             days: Int, travelMode: String? = nil, spots: [SharedTrip.Payload.Spot])
        -> SharedTrip.Payload.Stop {
        SharedTrip.Payload.Stop(city: city, countryCode: code, latitude: lat, longitude: lon, englishTitle: title,
                                days: days, travelMode: travelMode, places: spots)
    }

    private static func spot(_ name: String, _ category: PlaceCategory, _ lat: Double, _ lon: Double, _ day: Int,
                             _ wiki: String) -> SharedTrip.Payload.Spot {
        SharedTrip.Payload.Spot(name: name, category: category.rawValue, latitude: lat, longitude: lon, day: day,
                                wikipediaTitle: wiki, googlePlaceID: nil)
    }
}
#endif

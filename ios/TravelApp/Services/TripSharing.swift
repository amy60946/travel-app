import Combine
import CoreLocation
import CryptoKit
import Foundation

/// Herkese açık paylaşılan gezi (Oguz, 2026-11-02: herkese açık gezi ve
/// gezilerde arama; yorum, beğeni, mesajlaşma yok). Şehirler, günler ve
/// yerler paylaşılır; kişisel notlar, uçuş ve konaklama bilgileri paylaşılmaz.
struct SharedTrip: Identifiable, Codable, Hashable {
    let id: UUID
    var owner: UUID
    var localID: UUID
    var title: String
    var cities: [String]
    var countryCodes: [String]
    var days: Int
    var placeCount: Int
    /// Kapak fotoğrafı için ilk şehrin İngilizce Wikipedia başlığı.
    var coverTitle: String?
    var data: Payload?
    var author: Author?

    struct Author: Codable, Hashable {
        var name: String
        var emoji: String
    }

    enum CodingKeys: String, CodingKey {
        case id, owner, title, cities, days, data
        case localID = "local_id"
        case countryCodes = "country_codes"
        case placeCount = "place_count"
        case coverTitle = "cover_title"
        case author = "profiles"
    }

    /// Gezinin içeriği (sürüm 1).
    struct Payload: Codable, Hashable {
        var version = 1
        var stops: [Stop]

        struct Stop: Codable, Hashable {
            var city: String
            var countryCode: String?
            var latitude: Double
            var longitude: Double
            var englishTitle: String?
            var days: Int
            /// Bu şehre nasıl gelinir (araç, uçak...): yalnızca tür, ayrıntı yok.
            var travelMode: String?
            var places: [Spot]
        }

        struct Spot: Codable, Hashable, Identifiable {
            var id = UUID()
            var name: String
            var category: String
            var latitude: Double
            var longitude: Double
            /// Şehirdeki günü (0'dan).
            var day: Int
            var wikipediaTitle: String?
            var googlePlaceID: String?

            var placeCategory: PlaceCategory { PlaceCategory(rawValue: category) ?? .other }

            enum CodingKeys: String, CodingKey {
                case name, category, latitude, longitude, day, wikipediaTitle, googlePlaceID
            }
        }
    }

    /// "Tokyo, Kyoto · 7 gün · 24 yer"
    var summary: String {
        String(localized: "\(days) gün · \(placeCount) yer")
    }

    var flags: String { countryCodes.map(Country.flag).joined() }
}

/// Paylaşma, paylaşımı kaldırma, herkese açık gezileri listeleme ve arama.
/// Paylaşılan gezi değişince sunucudaki kopyası birkaç saniye sonra
/// kendiliğinden güncellenir.
@MainActor
final class TripSharing: ObservableObject {
    static let shared = TripSharing()

    /// Bu telefondaki paylaşılan gezilerin kimlikleri (gezi → son gönderilen içerik).
    @Published private(set) var sharedJourneys: [UUID: Int] = [:]

    private static let storageKey = "sharing.journeys"
    private var syncTask: Task<Void, Never>?
    private var observation: AnyCancellable?

    private static let listFields = "id,owner,local_id,title,cities,country_codes,days,place_count,cover_title,profiles(name,emoji)"

    init() {
        #if DEBUG
        if Account.demoScreen != nil { return }
        #endif
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([UUID: Int].self, from: data) {
            sharedJourneys = saved
        }
    }

    func isShared(_ journeyID: UUID) -> Bool { sharedJourneys[journeyID] != nil }

    #if DEBUG
    /// Ekran görüntüleri: örnek gezi paylaşılmış görünsün (sunucuya gitmez).
    func demoMarkShared(_ journeyID: UUID) {
        sharedJourneys[journeyID] = 0
    }
    #endif

    // MARK: - Kendi gezilerim

    /// Geziyi herkese açık paylaşır (ya da paylaşılmışsa günceller).
    func share(_ journey: Journey, store: AppStore) async throws {
        let account = Account.shared
        guard let userID = account.userID else { throw Supabase.Failure.signedOut }
        if account.profile == nil { try await account.loadProfile() }
        let token = try await account.validToken()
        let row = Self.row(for: journey, store: store, owner: userID)
        try await Supabase.send(try Supabase.request(
            "rest/v1/shared_trips", method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "owner,local_id")],
            json: [row.json], token: token, prefer: "resolution=merge-duplicates,return=minimal"))
        remember(journey.id, hash: row.hash)
    }

    /// Paylaşımı kaldırır: gezi yalnızca bu telefonda kalır.
    func unshare(_ journeyID: UUID) async throws {
        let account = Account.shared
        guard let userID = account.userID else { throw Supabase.Failure.signedOut }
        let token = try await account.validToken()
        try await Supabase.send(try Supabase.request("rest/v1/shared_trips", method: "DELETE", query: [
            URLQueryItem(name: "owner", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "local_id", value: "eq.\(journeyID.uuidString.lowercased())"),
        ], token: token))
        sharedJourneys[journeyID] = nil
        persist()
    }

    /// Girişten sonra: bu hesabın paylaştığı gezilerden bu telefonda olanlar
    /// (başka telefondan paylaşılanlara dokunulmaz).
    func refreshMine(store: AppStore) async {
        guard let userID = Account.shared.userID, let token = try? await Account.shared.validToken(),
              let request = try? Supabase.request("rest/v1/shared_trips", query: [
                  URLQueryItem(name: "owner", value: "eq.\(userID.uuidString.lowercased())"),
                  URLQueryItem(name: "select", value: "local_id"),
              ], token: token),
              let data = try? await Supabase.send(request) else { return }
        struct MineRow: Decodable { let local_id: UUID }
        guard let rows = try? Supabase.decoder.decode([MineRow].self, from: data) else { return }
        var updated: [UUID: Int] = [:]
        for row in rows where store.journey(row.local_id) != nil {
            updated[row.local_id] = sharedJourneys[row.local_id] ?? 0
        }
        sharedJourneys = updated
        persist()
    }

    /// Paylaşılan geziler değişince sunucudaki kopyaları güncellenir (5 sn
    /// bekleyip, değişen gezi için bir kez). Silinen gezinin paylaşımı kalkar.
    func startSync(with store: AppStore) {
        guard observation == nil, Supabase.isConfigured else { return }
        #if DEBUG
        if Account.demoScreen != nil { return }
        #endif
        observation = store.objectWillChange
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self, weak store] _ in
                Task { @MainActor in
                    guard let self, let store else { return }
                    self.syncTask?.cancel()
                    self.syncTask = Task { await self.sync(store) }
                }
            }
    }

    private func sync(_ store: AppStore) async {
        guard Account.shared.isSignedIn else { return }
        for (journeyID, hash) in sharedJourneys {
            guard !Task.isCancelled else { return }
            guard let journey = store.journey(journeyID) else {
                try? await unshare(journeyID)
                continue
            }
            let row = Self.row(for: journey, store: store, owner: Account.shared.userID ?? UUID())
            if row.hash != hash { try? await share(journey, store: store) }
        }
    }

    /// Çıkışta ya da hesap silinince.
    func forgetLocalState() {
        sharedJourneys = [:]
        persist()
    }

    private func remember(_ journeyID: UUID, hash: Int) {
        sharedJourneys[journeyID] = hash
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sharedJourneys) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Herkese açık geziler

    /// En yeni paylaşılan geziler; `query` verilirse başlıkta, şehirlerde ya
    /// da ülkelerde geçenler (Türkçe ya da İngilizce adla).
    func publicTrips(matching query: String = "", owner: UUID? = nil, limit: Int = 20) async throws -> [SharedTrip] {
        #if DEBUG
        if Account.demoScreen != nil { return SampleData.sharedTrips(matching: query, owner: owner) }
        #endif
        var items = [
            URLQueryItem(name: "select", value: Self.listFields),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        let folded = Self.fold(query)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for word in folded.prefix(4) {
            items.append(URLQueryItem(name: "search_text", value: "ilike.*\(word)*"))
        }
        if let owner { items.append(URLQueryItem(name: "owner", value: "eq.\(owner.uuidString.lowercased())")) }
        let data = try await Supabase.send(try Supabase.request("rest/v1/shared_trips", query: items))
        return try Supabase.decoder.decode([SharedTrip].self, from: data)
    }

    /// Bir paylaşılan gezinin tamamı (şehirler, günler, yerler).
    func trip(_ id: UUID) async throws -> SharedTrip? {
        #if DEBUG
        if Account.demoScreen != nil { return SampleData.sharedTrips().first { $0.id == id } }
        #endif
        let data = try await Supabase.send(try Supabase.request("rest/v1/shared_trips", query: [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: Self.listFields + ",data"),
        ]))
        return try Supabase.decoder.decode([SharedTrip].self, from: data).first
    }

    // MARK: - Gönderilen içerik

    struct Row {
        let json: [String: Any]
        let hash: Int
    }

    /// Sunucuya gidecek satır ve içeriğin özeti (değişti mi diye).
    static func row(for journey: Journey, store: AppStore, owner: UUID) -> Row {
        let payload = payload(for: journey, store: store)
        let title = String((journey.name.isEmpty ? Journey.defaultName(for: journey.stops.map(\.city)) : journey.name)
            .prefix(80))
        let cities = journey.stops.map(\.city)
        var codes: [String] = []
        for code in journey.stops.compactMap(\.countryCode) where !codes.contains(code) { codes.append(code) }
        let days = payload.stops.reduce(0) { $0 + $1.days }
        let placeCount = payload.stops.reduce(0) { $0 + $1.places.count }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(payload)) ?? Data()
        let dataObject = (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
        var json: [String: Any] = [
            "owner": owner.uuidString.lowercased(),
            "local_id": journey.id.uuidString.lowercased(),
            "title": title,
            "cities": cities,
            "country_codes": codes,
            "days": days,
            "place_count": placeCount,
            "search_text": searchText(title: title, cities: cities, countryCodes: codes),
            "data": dataObject,
        ]
        if let cover = journey.stops.first?.wikiTitle {
            json["cover_title"] = cover
        } else {
            json["cover_title"] = NSNull()
        }
        // Uygulama yeniden açılınca da aynı kalan özet (Hasher her açılışta değişir).
        let digest = SHA256.hash(data: Data(title.utf8) + data)
        let hash = digest.prefix(8).reduce(0) { ($0 << 8) | Int($1) }
        return Row(json: json, hash: hash)
    }

    static func payload(for journey: Journey, store: AppStore) -> SharedTrip.Payload {
        SharedTrip.Payload(stops: journey.stops.map { stop in
            let days = store.dayPlan(stop: stop.id)
            let spots = days.enumerated().flatMap { day, places in
                places.map { place in
                    SharedTrip.Payload.Spot(name: place.name, category: place.category.rawValue,
                                            latitude: place.latitude, longitude: place.longitude, day: day,
                                            wikipediaTitle: place.wikipediaTitle, googlePlaceID: place.googlePlaceID)
                }
            }
            return SharedTrip.Payload.Stop(city: stop.city, countryCode: stop.countryCode, latitude: stop.latitude,
                                           longitude: stop.longitude, englishTitle: stop.englishTitle,
                                           days: max(days.count, 1), travelMode: stop.arrivalMode?.rawValue,
                                           places: spots)
        })
    }

    /// Aramada bulunsun diye: başlık, şehirler ve ülkelerin Türkçe ve
    /// İngilizce adları; küçük harf, aksansız.
    nonisolated static func searchText(title: String, cities: [String], countryCodes: [String]) -> String {
        let countries = countryCodes.flatMap { code in
            ["tr_TR", "en_US"].compactMap { Locale(identifier: $0).localizedString(forRegionCode: code) }
        }
        return String(fold(([title] + cities + countries).joined(separator: " ")).prefix(2000))
    }

    nonisolated static func fold(_ text: String) -> String { Country.fold(text) }
}

extension AppStore {
    /// Paylaşılan geziyi kendi gezilerine kopyalar: şehirler, günler ve
    /// yerler gelir (yerler kayıtlarına da eklenir). Kimliğini döndürür.
    @discardableResult
    func copySharedTrip(_ shared: SharedTrip) -> UUID? {
        guard let payload = shared.data, !payload.stops.isEmpty else { return nil }
        let cities = payload.stops.map {
            CityChoice(name: $0.city, countryCode: $0.countryCode, latitude: $0.latitude, longitude: $0.longitude,
                       englishTitle: $0.englishTitle)
        }
        let journeyID = createJourney(name: shared.title, cities: cities)
        guard let journey = journey(journeyID) else { return journeyID }
        var configured = Set<UUID>()
        for (index, stop) in payload.stops.enumerated() {
            // Aynı şehir iki kez geçiyorsa (ya da adı birleştirildiyse) ilk durağa gider.
            let name = canonical(cities[index]).name
            guard let stopID = journey.stops.first(where: { $0.city == name })?.id else { continue }
            let days = max(stop.days, 1)
            setDays(configured.insert(stopID).inserted ? days : max(days, trip(stop: stopID).days), stop: stopID)
            for spot in stop.places {
                let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                let existing = spot.googlePlaceID.flatMap { savedPlace(googleID: $0, named: spot.name, near: coordinate) }
                    ?? savedPlace(named: spot.name, near: coordinate)
                if let existing {
                    plan(existing, stop: stopID, day: spot.day)
                } else {
                    var place = Place(name: spot.name, city: name, latitude: spot.latitude,
                                      longitude: spot.longitude, category: spot.placeCategory, source: .search)
                    place.wikipediaTitle = spot.wikipediaTitle
                    place.googlePlaceID = spot.googlePlaceID
                    add(place, plan: stopID, day: spot.day)
                }
            }
        }
        dismissUndo()
        return journeyID
    }
}

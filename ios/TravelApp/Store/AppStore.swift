import CoreLocation
import Foundation
import SwiftUI

/// Uygulamanın tüm durumu: kayıtlı yerler ve şehir planları.
/// Telefonda tek bir JSON dosyasında saklanır.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var places: [Place] = []
    @Published private(set) var trips: [Trip] = []
    /// Çok şehirli geziler (Polarsteps gibi): sırayla şehirler, uçuş ve konaklama.
    @Published private(set) var journeys: [Journey] = []
    /// Yeri bulunamayan kayıtlı gönderiler ("Yeri belirle" listesi).
    @Published private(set) var pendingPosts: [SocialExport.Post] = []
    /// Koleksiyonlar (Keşfet → Koleksiyonlar): ülke, şehir ve yer arşivi.
    @Published private(set) var collections: [PlaceCollection] = []
    /// Son işlem geri alınabiliyorsa gösterilecek mesaj.
    @Published private(set) var undoMessage: String?

    private struct Snapshot: Codable {
        var places: [Place]
        var trips: [Trip]
        var pendingPosts: [SocialExport.Post]?
        var journeys: [Journey]?
        var collections: [PlaceCollection]?
    }

    private var undoSnapshot: Snapshot?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TravelApp/state.json")
        load()
    }

    // MARK: - Şehirler

    struct CitySummary: Identifiable, Hashable {
        var name: String
        var placeCount: Int
        var latitude: Double
        var longitude: Double
        var hasTrip: Bool
        var coverPlace: Place?

        var id: String { name }
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    var cities: [CitySummary] {
        let grouped = Dictionary(grouping: places, by: \.city)
        var result: [CitySummary] = []
        for (name, list) in grouped {
            let count = Double(list.count)
            let latitude = list.reduce(0.0) { $0 + $1.latitude } / count
            let longitude = list.reduce(0.0) { $0 + $1.longitude } / count
            let hasTrip = trips.contains { $0.city == name }
            let cover = list.first { $0.wikipediaTitle != nil }
            result.append(CitySummary(name: name, placeCount: list.count, latitude: latitude,
                                      longitude: longitude, hasTrip: hasTrip, coverPlace: cover))
        }
        // Gezideki, henüz kayıtlı yeri olmayan şehirler (ör. yeni eklenen Ankara).
        for stop in journeys.flatMap(\.stops) where grouped[stop.city] == nil && !result.contains(where: { $0.name == stop.city }) {
            result.append(CitySummary(name: stop.city, placeCount: 0, latitude: stop.latitude,
                                      longitude: stop.longitude, hasTrip: true, coverPlace: nil))
        }
        // Gezisi olan şehirler önce, sonra ada göre.
        return result.sorted { a, b in
            if a.hasTrip != b.hasTrip { return a.hasTrip }
            return a.name < b.name
        }
    }

    func places(in city: String) -> [Place] {
        places.filter { $0.city == city }
    }

    func place(_ id: UUID) -> Place? {
        places.first { $0.id == id }
    }

    /// Şehrin haritadaki yeri: kayıtlı yerlerinin ortası, yoksa gezideki konumu.
    func center(of city: String) -> CLLocationCoordinate2D? {
        let list = places(in: city)
        if !list.isEmpty {
            let count = Double(list.count)
            return CLLocationCoordinate2D(latitude: list.reduce(0.0) { $0 + $1.latitude } / count,
                                          longitude: list.reduce(0.0) { $0 + $1.longitude } / count)
        }
        return journeys.flatMap(\.stops).first { $0.city == city }?.coordinate
    }

    // MARK: - Plan

    func trip(for city: String) -> Trip {
        trips.first { $0.city == city }
            ?? Trip(city: city, days: 2, pace: .normal, placeIDs: [], dayOf: [:])
    }

    func isPlanned(_ place: Place) -> Bool {
        trip(for: place.city).placeIDs.contains(place.id)
    }

    /// Şehrin günleri, yürüme sırasıyla. Her yerin gününü kullanıcı seçer
    /// (`Trip.dayOf`); gün içindeki sıra yürüme yoluna göre kendiliğinden.
    func dayPlan(for city: String) -> [[Place]] {
        let trip = self.trip(for: city)
        guard trip.days > 0 else { return [] }
        var days = Array(repeating: [Place](), count: trip.days)
        for place in trip.placeIDs.compactMap(place) {
            days[Self.clamp(trip.dayOf?[place.id] ?? 0, days: trip.days)].append(place)
        }
        return days.map { stops in
            let order = RoutePlanner.nearestNeighborOrder(stops.map(\.point))
            return order.compactMap { point in stops.first { $0.id == point.id } }
        }
    }

    func dayIndex(of place: Place) -> Int? {
        let trip = self.trip(for: place.city)
        guard trip.placeIDs.contains(place.id) else { return nil }
        return Self.clamp(trip.dayOf?[place.id] ?? 0, days: trip.days)
    }

    /// Gün sayısını değiştirir; silinen günlerin yerleri son güne geçer.
    func setDays(_ days: Int, city: String) {
        let days = min(max(days, 1), 14)
        let current = trip(for: city).days
        let message = days < current ? String(localized: "\(current). gün silindi") : nil
        updateTrip(city, undo: message) { trip in
            trip.days = days
            trip.dayOf = (trip.dayOf ?? [:]).mapValues { Self.clamp($0, days: days) }
        }
    }

    /// Yeri kullanıcının seçtiği güne taşır.
    func move(_ place: Place, toDay day: Int) {
        let trip = self.trip(for: place.city)
        guard (0..<trip.days).contains(day), let current = dayIndex(of: place), current != day else { return }
        updateTrip(place.city, undo: String(localized: "\(place.name) \(day + 1). güne taşındı")) {
            $0.dayOf = ($0.dayOf ?? [:]).merging([place.id: day]) { $1 }
        }
    }

    /// Yerleri rotaya, seçilen güne ekler.
    func addToPlan(_ ids: [UUID], city: String, day: Int = 0) {
        let day = Self.clamp(day, days: trip(for: city).days)
        updateTrip(city, undo: String(localized: "\(day + 1). güne eklendi")) { trip in
            for id in ids where !trip.placeIDs.contains(id) {
                trip.placeIDs.append(id)
                trip.dayOf = (trip.dayOf ?? [:]).merging([id: day]) { $1 }
            }
        }
    }

    func removeFromPlan(_ place: Place) {
        updateTrip(place.city, undo: String(localized: "\(place.name) rotadan çıkarıldı")) {
            $0.placeIDs.removeAll { $0 == place.id }
            $0.dayOf?[place.id] = nil
        }
    }

    private static func clamp(_ day: Int, days: Int) -> Int {
        min(max(day, 0), max(days - 1, 0))
    }

    /// Bu sürümden önceki gezilerde gün bilgisi yok: o zamanki otomatik
    /// bölme bir kez yapılıp kaydedilir, böylece hiçbir yer yer değiştirmez.
    private func withDays(_ trip: Trip) -> Trip {
        guard trip.dayOf == nil, trip.days > 0 else { return trip }
        var trip = trip
        let planned = trip.placeIDs.compactMap(place)
        let perDay = Int((Double(planned.count) / Double(trip.days)).rounded(.up))
        let plan = RoutePlanner.plan(planned.map(\.point), days: trip.days, maxPerDay: max(perDay, 1))
        var dayOf: [UUID: Int] = [:]
        for (index, ids) in plan.days.enumerated() {
            for id in ids { dayOf[id] = index }
        }
        trip.dayOf = dayOf
        return trip
    }

    // MARK: - Geziler (çok şehirli)

    func journey(_ id: UUID) -> Journey? {
        journeys.first { $0.id == id }
    }

    /// Gezideki şehirlerin gün sayıları, sırayla.
    func days(of journey: Journey) -> [Int] {
        journey.stops.map { trip(for: $0.city).days }
    }

    /// Şehir hangi gezide (ilk bulunan).
    func journey(containing city: String) -> Journey? {
        journeys.first { $0.stops.contains { $0.city == city } }
    }

    /// Yeni gezi; en yeni gezi listenin başında durur. Kimliğini döndürür.
    @discardableResult
    func createJourney(name: String? = nil, cities: [CityChoice]) -> UUID {
        let stops = uniqueStops(cities, existing: [])
        let journey = Journey(name: name ?? Journey.defaultName(for: stops.map(\.city)), stops: stops)
        snapshot(String(localized: "\(journey.name) gezisi oluşturuldu"))
        journeys.insert(journey, at: 0)
        stops.forEach { ensureTrip($0.city) }
        save()
        return journey.id
    }

    /// Şehirleri geziye, verilen sıraya (yoksa sona) ekler; gezide olanlar atlanır.
    func addStops(_ cities: [CityChoice], to journeyID: UUID, at index: Int? = nil) {
        guard let journey = self.journey(journeyID) else { return }
        let stops = uniqueStops(cities, existing: journey.stops)
        guard !stops.isEmpty else { return }
        let names = stops.map(\.city).joined(separator: ", ")
        updateJourney(journeyID, undo: String(localized: "\(names) eklendi")) { journey in
            let position = min(max(index ?? journey.stops.count, 0), journey.stops.count)
            journey.stops.insert(contentsOf: stops, at: position)
        }
        stops.forEach { ensureTrip($0.city) }
        save()
    }

    func removeStop(_ stopID: UUID, from journeyID: UUID) {
        guard let stop = journey(journeyID)?.stops.first(where: { $0.id == stopID }) else { return }
        updateJourney(journeyID, undo: String(localized: "\(stop.city) geziden çıkarıldı")) {
            $0.stops.removeAll { $0.id == stopID }
        }
    }

    /// Şehri gezide bir öne (-1) ya da bir sonraya (+1) taşır.
    func moveStop(_ stopID: UUID, by offset: Int, in journeyID: UUID) {
        updateJourney(journeyID) { journey in
            guard let index = journey.stops.firstIndex(where: { $0.id == stopID }) else { return }
            let target = index + offset
            guard journey.stops.indices.contains(target) else { return }
            journey.stops.swapAt(index, target)
        }
    }

    func renameJourney(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        updateJourney(id) { $0.name = name }
    }

    /// Geziyi siler; kayıtlı yerler durur, başka gezide olmayan şehirlerin
    /// planı (günler) silinir. Geri alınabilir.
    func deleteJourney(_ id: UUID) {
        guard let journey = self.journey(id) else { return }
        snapshot(String(localized: "\(journey.name) silindi"))
        journeys.removeAll { $0.id == id }
        let stillPlanned = Set(journeys.flatMap(\.stops).map(\.city))
        trips.removeAll { trip in journey.stops.contains { $0.city == trip.city } && !stillPlanned.contains(trip.city) }
        save()
    }

    func setFlight(_ flight: Flight?, stop stopID: UUID, in journeyID: UUID) {
        updateStop(stopID, in: journeyID, undo: flight == nil ? String(localized: "Uçuş silindi") : nil) {
            $0.flight = flight
        }
    }

    func addStay(_ stay: Stay, stop stopID: UUID, in journeyID: UUID) {
        updateStop(stopID, in: journeyID, undo: String(localized: "\(stay.name) eklendi")) {
            $0.stays.append(stay)
        }
    }

    func updateStay(_ stay: Stay, stop stopID: UUID, in journeyID: UUID) {
        updateStop(stopID, in: journeyID) { stop in
            guard let index = stop.stays.firstIndex(where: { $0.id == stay.id }) else { return }
            stop.stays[index] = stay
        }
    }

    func removeStay(_ stayID: UUID, stop stopID: UUID, in journeyID: UUID) {
        updateStop(stopID, in: journeyID, undo: String(localized: "Konaklama silindi")) {
            $0.stays.removeAll { $0.id == stayID }
        }
    }

    func setCountry(_ code: String, stop stopID: UUID, in journeyID: UUID) {
        updateStop(stopID, in: journeyID) { $0.countryCode = code }
    }

    /// Şehir 30 km içinde zaten kayıtlıysa (ör. "Istanbul" ile "İstanbul")
    /// kayıtlı adı kullanılır; böylece yerleri ve planı aynı şehirde kalır.
    func canonical(_ choice: CityChoice) -> CityChoice {
        let location = CLLocation(latitude: choice.latitude, longitude: choice.longitude)
        guard let known = cities.first(where: {
            $0.name == choice.name
                || CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) < 30_000
        }) else { return choice }
        var result = choice
        result.name = known.name
        return result
    }

    private func uniqueStops(_ cities: [CityChoice], existing: [Destination]) -> [Destination] {
        var names = Set(existing.map(\.city))
        return cities.map(canonical).compactMap { choice in
            names.insert(choice.name).inserted ? Destination(choice) : nil
        }
    }

    /// Şehrin planı yoksa boş bir plan açar (2 gün).
    private func ensureTrip(_ city: String) {
        if !trips.contains(where: { $0.city == city }) {
            trips.append(Trip(city: city, days: 2, pace: .normal, placeIDs: [], dayOf: [:]))
        }
    }

    /// Planı olan her şehir bir gezide görünsün: yoksa tek şehirlik gezi açılır.
    private func addJourneyIfMissing(for city: String) {
        guard journey(containing: city) == nil, let center = center(of: city) else { return }
        journeys.append(Journey(name: city, stops: [
            Destination(city: city, latitude: center.latitude, longitude: center.longitude),
        ]))
    }

    private func updateJourney(_ id: UUID, undo message: String? = nil, _ change: (inout Journey) -> Void) {
        guard let index = journeys.firstIndex(where: { $0.id == id }) else { return }
        if let message { snapshot(message) }
        change(&journeys[index])
        save()
    }

    private func updateStop(_ stopID: UUID, in journeyID: UUID, undo message: String? = nil,
                            _ change: (inout Destination) -> Void) {
        updateJourney(journeyID, undo: message) { journey in
            guard let index = journey.stops.firstIndex(where: { $0.id == stopID }) else { return }
            change(&journey.stops[index])
        }
    }

    // MARK: - Yerler

    /// Yeni yeri kaydeder; `plan` doğruysa rotaya, seçilen güne de ekler.
    func add(_ place: Place, plan: Bool, day: Int = 0) {
        snapshot(String(localized: "\(place.name) eklendi"))
        places.append(place)
        if plan {
            var trip = self.trip(for: place.city)
            trip.placeIDs.append(place.id)
            trip.dayOf = (trip.dayOf ?? [:]).merging([place.id: Self.clamp(day, days: trip.days)]) { $1 }
            replace(trip)
            addJourneyIfMissing(for: place.city)
        }
        save()
    }

    /// Bir yerin bilgilerini değiştirir ("Yanlış yer mi? Değiştir").
    func update(_ place: Place) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index] = place
        save()
    }

    /// Aynı adla 200 m içinde kayıtlı yer (haritadan eklerken iki kez
    /// kaydedilmesin).
    func savedPlace(named name: String, near coordinate: CLLocationCoordinate2D) -> Place? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return places.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.location.distance(from: location) < 200
        }
    }

    /// Haritada dokunulan Google yeri kayıtlı mı: Google kimliğiyle ya da
    /// aynı adla yakında.
    func savedPlace(googleID: String, named name: String, near coordinate: CLLocationCoordinate2D) -> Place? {
        places.first { $0.googlePlaceID == googleID } ?? savedPlace(named: name, near: coordinate)
    }

    /// Türü bilinmeyen ("Görülecek yer") aktarılmış yerlerin türünü bulur:
    /// önce addan, olmazsa Apple Haritalar'da aynı adla yakında arayarak.
    /// Haritadaki pinler böylece müze, kafe, tapınak diye ayrılır. Her yer
    /// bir kez denenir; Apple'ın dakikalık sınırına takılmamak için
    /// aramalar arasında beklenir.
    func refineCategories() async {
        let defaults = UserDefaults.standard
        var checked = Set(defaults.stringArray(forKey: Self.categoryCheckedKey) ?? [])
        let imported: Set<PlaceSource> = [.instagram, .tiktok, .googleMaps, .text]
        let candidates = places.filter {
            $0.category == .sight && imported.contains($0.source) && !checked.contains($0.id.uuidString)
        }
        for place in candidates {
            var category = PlaceCategory.guess(name: place.name)
            if category == nil {
                if Task.isCancelled { return }
                switch await PlaceSearch.category(of: place.name, near: place.coordinate) {
                case .throttled: return
                case .found(let found): category = found
                }
                try? await Task.sleep(for: .seconds(2))
            }
            checked.insert(place.id.uuidString)
            defaults.set(Array(checked), forKey: Self.categoryCheckedKey)
            // "Diğer" (istasyon, otopark...) büyük ihtimalle yanındaki yerdir; alınmaz.
            if let category, ![.sight, .other].contains(category), var current = self.place(place.id), current.category == .sight {
                current.category = category
                update(current)
            }
        }
    }

    private static let categoryCheckedKey = "categoryChecked"

    /// Aktarılan yerleri ekler; aynı ad ve yakın konumdakileri atlar.
    /// Yeri böylece bulunan gönderiler "Yeri belirle" listesinden çıkar.
    /// Eklenen sayısını döndürür.
    @discardableResult
    func importPlaces(_ newPlaces: [Place]) -> Int {
        let fresh = newPlaces.filter { candidate in
            !places.contains { existing in
                existing.name.caseInsensitiveCompare(candidate.name) == .orderedSame
                    && existing.location.distance(from: candidate.location) < 200
            }
        }
        let resolved = Set(newPlaces.compactMap { $0.sourceURL.map(SocialExport.canonical) })
        let pendingCount = pendingPosts.count
        if !fresh.isEmpty {
            snapshot(String(localized: "\(fresh.count) yer aktarıldı"))
            places.append(contentsOf: fresh)
        }
        pendingPosts.removeAll { resolved.contains(SocialExport.canonical($0.url)) }
        if !fresh.isEmpty || pendingPosts.count != pendingCount { save() }
        return fresh.count
    }

    // MARK: - Yeri belirlenecek gönderiler

    /// Yeni gönderileri listeye ekler; listede olanları ve yeri zaten
    /// bulunanları atlar.
    func addPending(_ posts: [SocialExport.Post]) {
        let known = Set(pendingPosts.map { SocialExport.canonical($0.url) })
            .union(places.compactMap { $0.sourceURL.map(SocialExport.canonical) })
        var added = Set<String>()
        for post in posts {
            let key = SocialExport.canonical(post.url)
            guard !known.contains(key), added.insert(key).inserted else { continue }
            pendingPosts.append(post)
        }
        save()
    }

    func removePending(_ post: SocialExport.Post) {
        pendingPosts.removeAll { $0.id == post.id }
        save()
    }

    /// Yeri daha önce bulunmuş gönderi (yeniden aktarımda atlanır;
    /// "Yeri belirle" listesindekiler yeniden denenir).
    func hasPlace(_ post: SocialExport.Post) -> Bool {
        let key = SocialExport.canonical(post.url)
        return places.contains { $0.sourceURL.map(SocialExport.canonical) == key }
    }

    // MARK: - Koleksiyonlar

    func collection(_ id: UUID) -> PlaceCollection? {
        collections.first { $0.id == id }
    }

    /// Yeni koleksiyon; `item` verilirse içine de eklenir.
    @discardableResult
    func createCollection(name: String, emoji: String, color: Int, with item: CollectionItem? = nil) -> UUID {
        var collection = PlaceCollection(name: name, emoji: emoji, color: color)
        if let item { collection.items.append(item) }
        collections.insert(collection, at: 0)
        save()
        return collection.id
    }

    func editCollection(_ id: UUID, name: String, emoji: String, color: Int) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = name
        collections[index].emoji = emoji
        collections[index].color = color
        save()
    }

    func deleteCollection(_ id: UUID) {
        guard let collection = collection(id) else { return }
        snapshot(String(localized: "\(collection.name) silindi"))
        collections.removeAll { $0.id == id }
        save()
    }

    func contains(_ item: CollectionItem, in collectionID: UUID) -> Bool {
        collection(collectionID)?.items.contains { $0.key == item.key } ?? false
    }

    /// Herhangi bir koleksiyonda mı (kaydet düğmesi dolu görünsün).
    func isCollected(_ item: CollectionItem) -> Bool {
        collections.contains { $0.items.contains { $0.key == item.key } }
    }

    /// Koleksiyonda yoksa ekler, varsa çıkarır.
    func toggle(_ item: CollectionItem, in collectionID: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        let name = collections[index].name
        if let existing = collections[index].items.firstIndex(where: { $0.key == item.key }) {
            snapshot(String(localized: "\(item.displayName) \(name) koleksiyonundan çıkarıldı"))
            collections[index].items.remove(at: existing)
        } else {
            snapshot(String(localized: "\(item.displayName) \(name) koleksiyonuna eklendi"))
            collections[index].items.insert(item, at: 0)
        }
        save()
    }

    func removeItem(_ itemID: UUID, from collectionID: UUID) {
        guard let item = collection(collectionID)?.items.first(where: { $0.id == itemID }) else { return }
        toggle(item, in: collectionID)
    }

    // MARK: - Geri al

    func undo() {
        guard let undoSnapshot else { return }
        places = undoSnapshot.places
        trips = undoSnapshot.trips
        pendingPosts = undoSnapshot.pendingPosts ?? pendingPosts
        journeys = undoSnapshot.journeys ?? journeys
        collections = undoSnapshot.collections ?? collections
        self.undoSnapshot = nil
        undoMessage = nil
        save()
    }

    func dismissUndo() {
        undoMessage = nil
    }

    // MARK: - Yardımcılar

    private func updateTrip(_ city: String, undo message: String? = nil, _ change: (inout Trip) -> Void) {
        if let message { snapshot(message) }
        var trip = self.trip(for: city)
        change(&trip)
        replace(trip)
        addJourneyIfMissing(for: city)
        save()
    }

    private func replace(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.city == trip.city }) {
            trips[index] = trip
        } else {
            trips.append(trip)
        }
    }

    private func snapshot(_ message: String) {
        undoSnapshot = Snapshot(places: places, trips: trips, pendingPosts: pendingPosts, journeys: journeys,
                                collections: collections)
        undoMessage = message
    }

    private func load() {
        var needsJourneys = true
        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(Snapshot.self, from: data) {
            places = state.places
            trips = state.trips
            pendingPosts = state.pendingPosts ?? []
            journeys = state.journeys ?? []
            collections = state.collections ?? []
            needsJourneys = state.journeys == nil
        } else {
            places = SampleData.places
            trips = SampleData.trips(for: places)
        }
        trips = trips.map(withDays)
        // Çok şehirli gezilerden önceki şehir planları bir kez birer şehirlik gezi olur.
        if needsJourneys {
            for trip in trips where !trip.placeIDs.isEmpty {
                addJourneyIfMissing(for: trip.city)
            }
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let state = Snapshot(places: places, trips: trips, pendingPosts: pendingPosts, journeys: journeys,
                                 collections: collections)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            print("Kayıt yazılamadı: \(error)")
        }
    }
}

private extension Place {
    var point: RoutePlanner.Point {
        RoutePlanner.Point(id: id, latitude: latitude, longitude: longitude)
    }
}

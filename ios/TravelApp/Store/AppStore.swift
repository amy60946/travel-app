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

    /// Gezideki bir şehir: gezisi ve durağı.
    struct StopRef: Identifiable, Hashable {
        var journey: Journey
        var stop: Destination
        var id: UUID { stop.id }
    }

    func stop(_ id: UUID) -> StopRef? {
        for journey in journeys {
            if let stop = journey.stops.first(where: { $0.id == id }) { return StopRef(journey: journey, stop: stop) }
        }
        return nil
    }

    /// Bu şehrin geçtiği geziler (en yeni gezi önce).
    func stops(in city: String) -> [StopRef] {
        journeys.flatMap { journey in
            journey.stops.filter { $0.city == city }.map { StopRef(journey: journey, stop: $0) }
        }
    }

    /// Şehrin rotası için gezi şehri: şehrin geçtiği ilk gezi; yoksa tek
    /// şehirlik yeni gezi açılır.
    func planStop(for city: String) -> UUID {
        if let ref = stops(in: city).first { return ref.id }
        let middle = center(of: city) ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let stop = Destination(city: city, latitude: middle.latitude, longitude: middle.longitude)
        journeys.insert(Journey(name: city, stops: [stop]), at: 0)
        ensureTrip(stop)
        save()
        return stop.id
    }

    /// Gezideki şehrin planı; henüz yoksa boş plan (2 gün).
    func trip(stop id: UUID) -> Trip {
        trips.first { $0.stopID == id }
            ?? Trip(city: stop(id)?.stop.city ?? "", days: 2, stopID: id)
    }

    /// Yer herhangi bir gezinin rotasında mı.
    func isPlanned(_ place: Place) -> Bool {
        trips.contains { $0.placeIDs.contains(place.id) }
    }

    /// Yer bu gezi şehrinin rotasında mı (koleksiyonda olması sayılmaz).
    func isPlanned(_ place: Place, stop: UUID) -> Bool {
        trip(stop: stop).placeIDs.contains(place.id)
    }

    /// Yerin bulunduğu geziler ve günü ("Tokyo · 2. gün").
    struct PlanSlot: Identifiable, Hashable {
        var ref: StopRef
        var day: Int
        var id: UUID { ref.id }
    }

    func plans(containing place: Place) -> [PlanSlot] {
        journeys.flatMap { journey in
            journey.stops.compactMap { stop in
                dayIndex(of: place, stop: stop.id).map { PlanSlot(ref: StopRef(journey: journey, stop: stop), day: $0) }
            }
        }
    }

    /// Şehrin günleri. Her yerin gününü kullanıcı seçer (`Trip.dayOf`); gün
    /// içindeki sıra elle sıralandıysa o sıra, yoksa yürüme yoluna göre.
    func dayPlan(stop id: UUID) -> [[Place]] {
        let trip = self.trip(stop: id)
        guard trip.days > 0 else { return [] }
        var days = Array(repeating: [Place](), count: trip.days)
        for place in trip.placeIDs.compactMap(place) {
            days[Self.clamp(trip.dayOf?[place.id] ?? 0, days: trip.days)].append(place)
        }
        return days.enumerated().map { index, stops in
            if trip.manualDays?.contains(index) == true { return stops }
            let order = RoutePlanner.nearestNeighborOrder(stops.map(\.point))
            return order.compactMap { point in stops.first { $0.id == point.id } }
        }
    }

    /// Şehrin bütün gezilerdeki günleri, art arda (indirme için).
    func dayPlans(in city: String) -> [[Place]] {
        stops(in: city).flatMap { dayPlan(stop: $0.id) }
    }

    func dayIndex(of place: Place, stop id: UUID) -> Int? {
        let trip = self.trip(stop: id)
        guard trip.placeIDs.contains(place.id) else { return nil }
        return Self.clamp(trip.dayOf?[place.id] ?? 0, days: trip.days)
    }

    /// Gün elle mi sıralandı ("Yürüme sırasına diz" görünür).
    func isManuallyOrdered(day: Int, stop id: UUID) -> Bool {
        trip(stop: id).manualDays?.contains(day) == true
    }

    /// Gün sayısını değiştirir; silinen günlerin yerleri son güne geçer.
    func setDays(_ days: Int, stop id: UUID) {
        let days = min(max(days, 1), 14)
        let current = trip(stop: id).days
        let message = days < current ? String(localized: "\(current). gün silindi") : nil
        updateTrip(id, undo: message) { trip in
            trip.days = days
            trip.dayOf = (trip.dayOf ?? [:]).mapValues { Self.clamp($0, days: days) }
            trip.manualDays = trip.manualDays?.filter { $0 < days }
        }
    }

    /// Yeri kullanıcının seçtiği güne taşır (elle sıralanan günde sona).
    func move(_ place: Place, toDay day: Int, stop id: UUID) {
        let trip = self.trip(stop: id)
        guard (0..<trip.days).contains(day), let current = dayIndex(of: place, stop: id), current != day else { return }
        updateTrip(id, undo: String(localized: "\(place.name) \(day + 1). güne taşındı")) {
            $0.dayOf = ($0.dayOf ?? [:]).merging([place.id: day]) { $1 }
            $0.placeIDs.removeAll { $0 == place.id }
            $0.placeIDs.append(place.id)
        }
    }

    /// Basılı tutup sürükleme: yeri `target`ın önüne (yoksa günün sonuna)
    /// koyar; başka günden geldiyse gününü de değiştirir. Gün artık elle
    /// sıralanmış sayılır.
    func reorder(_ place: Place, before target: Place?, day: Int, stop id: UUID) {
        let trip = self.trip(stop: id)
        guard trip.placeIDs.contains(place.id), (0..<trip.days).contains(day), target?.id != place.id else { return }
        var order = dayPlan(stop: id)[day].map(\.id).filter { $0 != place.id }
        let index = target.flatMap { target in order.firstIndex(of: target.id) } ?? order.count
        order.insert(place.id, at: index)
        let from = dayIndex(of: place, stop: id)
        let message = from == day ? String(localized: "\(place.name) taşındı")
                                  : String(localized: "\(place.name) \(day + 1). güne taşındı")
        updateTrip(id, undo: message) { trip in
            trip.placeIDs = trip.placeIDs.filter { !order.contains($0) } + order
            trip.dayOf = (trip.dayOf ?? [:]).merging([place.id: day]) { $1 }
            trip.manualDays = (trip.manualDays ?? []).union([day])
        }
    }

    /// Günü yeniden yürüme yoluna göre sıralar (elle sıralamayı bırakır).
    func orderByWalking(day: Int, stop id: UUID) {
        updateTrip(id, undo: String(localized: "\(day + 1). gün yürüme sırasına dizildi")) {
            $0.manualDays?.remove(day)
        }
    }

    /// Yerleri rotaya, seçilen güne ekler.
    func addToPlan(_ ids: [UUID], stop id: UUID, day: Int = 0) {
        let day = Self.clamp(day, days: trip(stop: id).days)
        updateTrip(id, undo: String(localized: "\(day + 1). güne eklendi")) { trip in
            for placeID in ids where !trip.placeIDs.contains(placeID) {
                trip.placeIDs.append(placeID)
                trip.dayOf = (trip.dayOf ?? [:]).merging([placeID: day]) { $1 }
            }
        }
    }

    /// Kayıtlı bir yeri (ör. bir koleksiyondaki) bu gezi şehrinin rotasına,
    /// seçilen güne ekler; yer koleksiyonlarında da kalır. Yer başka bir
    /// şehir adıyla kaydedildiyse (ör. semt adıyla) ve hiçbir rotada
    /// değilse bu şehre geçer.
    func plan(_ place: Place, stop id: UUID, day: Int) {
        guard let city = stop(id)?.stop.city else { return }
        let day = Self.clamp(day, days: trip(stop: id).days)
        let moves = place.city != city && !isPlanned(place)
        updateTrip(id, undo: String(localized: "\(day + 1). güne eklendi")) { trip in
            if moves, let index = places.firstIndex(where: { $0.id == place.id }) { places[index].city = city }
            if !trip.placeIDs.contains(place.id) { trip.placeIDs.append(place.id) }
            trip.dayOf = (trip.dayOf ?? [:]).merging([place.id: day]) { $1 }
        }
    }

    func removeFromPlan(_ place: Place, stop id: UUID) {
        updateTrip(id, undo: String(localized: "\(place.name) rotadan çıkarıldı")) {
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
        journey.stops.map { trip(stop: $0.id).days }
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
        stops.forEach(ensureTrip)
        save()
        return journey.id
    }

    /// Koleksiyondan yeni gezi: koleksiyonun şehirleri ve yerlerinin
    /// şehirleri durak olur (koleksiyona ilk eklenen önce); her yer kendi
    /// şehrinin 1. gününe eklenir (günleri kullanıcı seçer). Yerler
    /// koleksiyonda da kalır; ülkeler alınmaz.
    @discardableResult
    func createJourney(from collectionID: UUID) -> UUID? {
        guard let collection = collection(collectionID) else { return nil }
        var stops: [Destination] = []
        var planned: [String: [UUID]] = [:]
        // Aynı şehir (ör. "Shibuya" semti ile "Tokyo") tek durak olur.
        func stopCity(_ choice: CityChoice) -> String {
            let choice = canonical(choice)
            if !stops.contains(where: { $0.city == choice.name }) { stops.append(Destination(choice)) }
            return choice.name
        }
        for item in collection.items.reversed() {
            switch item.kind {
            case .city:
                guard let latitude = item.latitude, let longitude = item.longitude else { continue }
                _ = stopCity(CityChoice(name: item.name, countryCode: item.countryCode, latitude: latitude,
                                        longitude: longitude, englishTitle: item.englishTitle))
            case .place:
                guard let place = item.placeID.flatMap(place), let center = center(of: place.city) else { continue }
                let city = stopCity(CityChoice(name: place.city, latitude: center.latitude, longitude: center.longitude))
                if planned[city]?.contains(place.id) != true { planned[city, default: []].append(place.id) }
            case .country:
                continue
            }
        }
        guard !stops.isEmpty else { return nil }
        let journey = Journey(name: collection.name, stops: stops)
        snapshot(String(localized: "\(journey.name) gezisi oluşturuldu"))
        journeys.insert(journey, at: 0)
        for stop in stops {
            let ids = planned[stop.city] ?? []
            trips.append(Trip(city: stop.city, days: 2, placeIDs: ids,
                              dayOf: Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) }), stopID: stop.id))
        }
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
        stops.forEach(ensureTrip)
        save()
    }

    func removeStop(_ stopID: UUID, from journeyID: UUID) {
        guard let stop = journey(journeyID)?.stops.first(where: { $0.id == stopID }) else { return }
        snapshot(String(localized: "\(stop.city) geziden çıkarıldı"))
        trips.removeAll { $0.stopID == stopID }
        updateJourney(journeyID) {
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

    /// Geziyi ve şehirlerinin planlarını (günler) siler; kayıtlı yerler
    /// durur. Geri alınabilir.
    func deleteJourney(_ id: UUID) {
        guard let journey = self.journey(id) else { return }
        snapshot(String(localized: "\(journey.name) silindi"))
        journeys.removeAll { $0.id == id }
        let stopIDs = Set(journey.stops.map(\.id))
        trips.removeAll { $0.stopID.map(stopIDs.contains) ?? false }
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

    /// Gezi şehrinin planı yoksa boş bir plan açar (2 gün).
    private func ensureTrip(_ stop: Destination) {
        if !trips.contains(where: { $0.stopID == stop.id }) {
            trips.append(Trip(city: stop.city, days: 2, stopID: stop.id))
        }
    }

    /// Eski kayıtlarda planı olan her şehir bir gezide görünsün: yoksa tek
    /// şehirlik gezi açılır.
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

    /// Yeni yeri kaydeder; `plan` verilirse o gezi şehrinin rotasına,
    /// seçilen güne de ekler.
    func add(_ place: Place, plan stopID: UUID? = nil, day: Int = 0) {
        snapshot(String(localized: "\(place.name) eklendi"))
        places.append(place)
        if let stopID {
            var trip = self.trip(stop: stopID)
            trip.placeIDs.append(place.id)
            trip.dayOf = (trip.dayOf ?? [:]).merging([place.id: Self.clamp(day, days: trip.days)]) { $1 }
            replace(trip)
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

    private func updateTrip(_ stopID: UUID, undo message: String? = nil, _ change: (inout Trip) -> Void) {
        guard stop(stopID) != nil else { return }
        if let message { snapshot(message) }
        var trip = self.trip(stop: stopID)
        change(&trip)
        replace(trip)
        save()
    }

    private func replace(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.stopID == trip.stopID }) {
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
        attachPlansToStops()
    }

    /// Planlar eskiden şehre bağlıydı (aynı şehir iki gezide aynı planı
    /// paylaşıyordu); artık her gezinin şehri kendi planını tutar. Eski
    /// plan, o şehri içeren her gezi şehrine bir kez kopyalanır.
    private func attachPlansToStops() {
        let legacy = trips.filter { $0.stopID == nil }
        guard !legacy.isEmpty || journeys.flatMap(\.stops).contains(where: { stop in
            !trips.contains { $0.stopID == stop.id }
        }) else { return }
        for trip in legacy where !trip.placeIDs.isEmpty { addJourneyIfMissing(for: trip.city) }
        var attached = trips.filter { $0.stopID != nil }
        for stop in journeys.flatMap(\.stops) where !attached.contains(where: { $0.stopID == stop.id }) {
            var trip = legacy.first { $0.city == stop.city } ?? Trip(city: stop.city, days: 2)
            trip.stopID = stop.id
            attached.append(trip)
        }
        trips = attached
        save()
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

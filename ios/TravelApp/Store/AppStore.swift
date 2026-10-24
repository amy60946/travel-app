import CoreLocation
import Foundation
import SwiftUI

/// Uygulamanın tüm durumu: kayıtlı yerler ve şehir planları.
/// Telefonda tek bir JSON dosyasında saklanır.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var places: [Place] = []
    @Published private(set) var trips: [Trip] = []
    /// Yeri bulunamayan kayıtlı gönderiler ("Yeri belirle" listesi).
    @Published private(set) var pendingPosts: [SocialExport.Post] = []
    /// Son işlem geri alınabiliyorsa gösterilecek mesaj.
    @Published private(set) var undoMessage: String?

    private struct Snapshot: Codable {
        var places: [Place]
        var trips: [Trip]
        var pendingPosts: [SocialExport.Post]?
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

    // MARK: - Plan

    func trip(for city: String) -> Trip {
        trips.first { $0.city == city }
            ?? Trip(city: city, days: 2, pace: .normal, placeIDs: [])
    }

    func isPlanned(_ place: Place) -> Bool {
        trip(for: place.city).placeIDs.contains(place.id)
    }

    /// Şehrin günleri, yürüme sırasıyla.
    func dayPlan(for city: String) -> (days: [[Place]], leftOver: [Place]) {
        let trip = self.trip(for: city)
        let points = trip.placeIDs.compactMap(place).map {
            RoutePlanner.Point(id: $0.id, latitude: $0.latitude, longitude: $0.longitude)
        }
        let plan = RoutePlanner.plan(points, days: trip.days, maxPerDay: trip.pace.stopsPerDay.upperBound)
        return (plan.days.map { $0.compactMap(place) }, plan.leftOver.compactMap(place))
    }

    func dayIndex(of place: Place) -> Int? {
        dayPlan(for: place.city).days.firstIndex { $0.contains { $0.id == place.id } }
    }

    func setDays(_ days: Int, city: String) {
        updateTrip(city) { $0.days = min(max(days, 1), 14) }
    }

    func setPace(_ pace: Pace, city: String) {
        updateTrip(city) { $0.pace = pace }
    }

    func addToPlan(_ ids: [UUID], city: String) {
        updateTrip(city, undo: String(localized: "Rotaya eklendi")) { trip in
            for id in ids where !trip.placeIDs.contains(id) { trip.placeIDs.append(id) }
        }
    }

    func removeFromPlan(_ place: Place) {
        updateTrip(place.city, undo: String(localized: "\(place.name) rotadan çıkarıldı")) {
            $0.placeIDs.removeAll { $0 == place.id }
        }
    }

    /// Günün son durağını rotadan çıkarır.
    func lightenDay(_ index: Int, city: String) {
        let days = dayPlan(for: city).days
        guard days.indices.contains(index), let last = days[index].last else { return }
        removeFromPlan(last)
    }

    // MARK: - Yerler

    /// Yeni yeri kaydeder; `plan` doğruysa rotaya da ekler.
    func add(_ place: Place, plan: Bool) {
        snapshot(String(localized: "\(place.name) eklendi"))
        places.append(place)
        if plan {
            var trip = self.trip(for: place.city)
            trip.placeIDs.append(place.id)
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

    /// Aktarılan yerleri ekler; aynı ad ve yakın konumdakileri atlar.
    /// Eklenen sayısını döndürür.
    @discardableResult
    func importPlaces(_ newPlaces: [Place]) -> Int {
        let fresh = newPlaces.filter { candidate in
            !places.contains { existing in
                existing.name.caseInsensitiveCompare(candidate.name) == .orderedSame
                    && existing.location.distance(from: candidate.location) < 200
            }
        }
        guard !fresh.isEmpty else { return 0 }
        snapshot(String(localized: "\(fresh.count) yer aktarıldı"))
        places.append(contentsOf: fresh)
        save()
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

    /// Daha önce aktarılmış gönderiler (yeniden aktarımda atlanır).
    func isKnown(_ post: SocialExport.Post) -> Bool {
        let key = SocialExport.canonical(post.url)
        return pendingPosts.contains { SocialExport.canonical($0.url) == key }
            || places.contains { $0.sourceURL.map(SocialExport.canonical) == key }
    }

    // MARK: - Geri al

    func undo() {
        guard let undoSnapshot else { return }
        places = undoSnapshot.places
        trips = undoSnapshot.trips
        pendingPosts = undoSnapshot.pendingPosts ?? pendingPosts
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
        undoSnapshot = Snapshot(places: places, trips: trips, pendingPosts: pendingPosts)
        undoMessage = message
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(Snapshot.self, from: data) {
            places = state.places
            trips = state.trips
            pendingPosts = state.pendingPosts ?? []
        } else {
            places = SampleData.places
            trips = SampleData.trips(for: places)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let state = Snapshot(places: places, trips: trips, pendingPosts: pendingPosts)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            print("Kayıt yazılamadı: \(error)")
        }
    }
}

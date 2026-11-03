import CoreLocation
import SwiftUI

/// Yer penceresinde "Buna bakanlar şunlara da baktı": Wikipedia okurlarının
/// bu yerin sayfasından sonra en çok baktığı yakın yerler (okuma izleri,
/// ReadingTrails). "+" yeri bu yerin gününe ekler; bu yer hiçbir gezide
/// değilse yer kaydedilir ve "Nereye eklensin?" sorulur.
struct AlsoReadSection: View {
    let place: Place
    let items: [WikipediaService.PopularPlace]
    var stop: UUID?
    var fallbackDay = 0
    @EnvironmentObject private var store: AppStore
    @State private var destination: Place?

    /// Yerin sayfasına bakanların en çok baktığı, 6 km içindeki en çok 4 yer
    /// (gezilecek yer olmayanlar çıkar). `englishTitle` yoksa liste boş.
    static func load(for place: Place, englishTitle: String?) async -> [WikipediaService.PopularPlace] {
        guard let englishTitle else { return [] }
        let related = await ReadingTrails.shared.related(to: englishTitle, latitude: place.latitude,
                                                         longitude: place.longitude)
            .filter { place.location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 6000 }
        let places = await WikipediaService.shared.places(Array(related.prefix(10)))
        return Array(places.prefix(4))
    }

    /// Bu yer bir rotadaysa o gezi şehri ve günü.
    private var slot: (stop: UUID, day: Int)? {
        if let stop { return (stop: stop, day: store.dayIndex(of: place, stop: stop) ?? fallbackDay) }
        return store.plans(containing: place).first.map { (stop: $0.ref.id, day: $0.day) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Buna bakanlar şunlara da baktı").font(Theme.headline)
            ForEach(items) { row($0) }
        }
        .sheet(item: $destination) { SaveToCollectionSheet(item: .place($0), place: $0) }
    }

    private func row(_ item: WikipediaService.PopularPlace) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        let saved = store.savedPlace(named: item.name, near: coordinate)
            ?? store.savedPlace(named: item.title, near: coordinate)
        let category = saved?.category ?? PlaceCategory.guess(name: item.title) ?? .sight
        return SpotRow(category: category, title: item.name, subtitle: walkText(to: coordinate),
                       isAdded: isAdded(saved), onAdd: { add(item, category: category, saved: saved) }) {
            LocationPhoto(name: item.name, category: category, city: place.city,
                          latitude: item.latitude, longitude: item.longitude, englishTitle: item.title,
                          knownPhoto: item.thumbnailURL, size: 64, cornerRadius: 14)
        }
    }

    /// Bu yerden yürüyerek (gerçek süre biliniyorsa o; yoksa kuş uçuşu × 1,3, dakikada 80 m).
    private func walkText(to coordinate: CLLocationCoordinate2D) -> String {
        let minutes = WalkingTimes.shared.walk(place.coordinate, coordinate)?.minutes
            ?? place.location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) * 1.3 / 80
        return String(localized: "yürüyerek \(max(Int(minutes.rounded()), 1)) dk")
    }

    private func isAdded(_ saved: Place?) -> Bool {
        guard let saved else { return false }
        guard let slot else { return true }
        return store.dayIndex(of: saved, stop: slot.stop) != nil
    }

    private func add(_ item: WikipediaService.PopularPlace, category: PlaceCategory, saved: Place?) {
        if let saved {
            guard let slot else {
                destination = saved
                return
            }
            if store.dayIndex(of: saved, stop: slot.stop) != nil {
                store.removeFromPlan(saved, stop: slot.stop)
            } else {
                store.plan(saved, stop: slot.stop, day: slot.day)
            }
            return
        }
        let new = Place(name: item.name, city: place.city, latitude: item.latitude, longitude: item.longitude,
                        category: category, source: .search, wikipediaTitle: item.title)
        if let slot {
            store.add(new, plan: slot.stop, day: slot.day)
        } else {
            store.add(new)
            destination = new
        }
    }
}

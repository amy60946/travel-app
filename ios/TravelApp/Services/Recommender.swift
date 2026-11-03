import CoreLocation
import Foundation

/// "Yer ekle"deki "Yakınındaki popüler yerler": günün yerlerine yürüme
/// mesafesindeki, en çok gezilen yerler. Sabit bir liste değil; güne yer
/// eklendikçe, gün değişince yeniden hesaplanır.
///
/// Benzer uygulamalardan (2026-11-03): Google Maps yakındaki yerleri
/// alaka, uzaklık ve bilinirlikle sıralar; Wanderlog plandaki yerlerin
/// çevresinden öneri verir; Tripadvisor her yerin sayfasında "Yakındakiler"
/// gösterir; Polarsteps bölgenin popüler yerlerini listeler. Burada aynı
/// sinyaller ücretsiz verilerle birleşir:
/// - bilinirlik: Wikipedia sayfasının son 30 gündeki okunma sayısı,
/// - yakınlık: günün en yakın yerine yürüme mesafesi (2 km'den uzak yok),
/// - zevk: kullanıcının kayıtlı yerlerinde o türün payı,
/// - çeşitlilik: günde aynı türden çok yer varsa o tür biraz geride.
enum Recommender {
    struct Suggestion: Identifiable, Equatable {
        var place: WikipediaService.PopularPlace
        var category: PlaceCategory
        /// En yakın günün yeri (alt yazıda "Kız Kulesi yakınında").
        var anchorName: String
        var distance: CLLocationDistance
        var score: Double
        var id: String { place.id }

        /// Yürüyerek yaklaşık dakika (yol düz çizgiden ~%30 uzun, dakikada 80 m).
        var walkingMinutes: Int { max(Int((distance * 1.3 / 80).rounded()), 1) }
    }

    /// Bir yere bu kadar uzaktakiler önerilmez.
    static let maxDistance: CLLocationDistance = 2000
    /// Yakınlığın etkisi: ~900 m'de yarıya yakın düşer (12 dk yürüme).
    private static let distanceScale: CLLocationDistance = 900

    /// Adayları puanlar ve sıralar. `excluded`: zaten rotada olanlar.
    static func rank(_ candidates: [WikipediaService.PopularPlace], anchors: [Place], saved: [Place],
                     excluded: (WikipediaService.PopularPlace) -> Bool = { _ in false },
                     limit: Int = 20) -> [Suggestion] {
        guard !anchors.isEmpty else { return [] }
        var unique: [String: WikipediaService.PopularPlace] = [:]
        for candidate in candidates where !excluded(candidate) {
            if let existing = unique[candidate.title], existing.monthlyViews >= candidate.monthlyViews { continue }
            unique[candidate.title] = candidate
        }
        let tastes = shares(saved.map(\.category))
        let dayCounts = Dictionary(anchors.map { ($0.category, 1) }, uniquingKeysWith: +)
        // Önce uzaklık: bilinirlik yalnızca yürüme mesafesindekiler arasında karşılaştırılır.
        let near: [(candidate: WikipediaService.PopularPlace, anchor: Place, distance: CLLocationDistance)] =
            unique.values.compactMap { candidate in
                let location = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
                guard let nearest = anchors.min(by: {
                    $0.location.distance(from: location) < $1.location.distance(from: location)
                }) else { return nil }
                let distance = nearest.location.distance(from: location)
                return distance <= maxDistance ? (candidate, nearest, distance) : nil
            }
        let maxViews = near.map(\.candidate.monthlyViews).max() ?? 0

        let suggestions: [Suggestion] = near.map { candidate, nearest, distance in
            let category = PlaceCategory.guess(name: candidate.title) ?? .sight
            let popularity: Double = maxViews > 0 ? log10(1 + Double(candidate.monthlyViews)) / log10(1 + Double(maxViews)) : 0
            let proximity = exp(-distance / distanceScale)
            let taste: Double = saved.isEmpty ? 1 : 0.85 + 0.3 * (tastes[category] ?? 0)
            let sameKind = dayCounts[category] ?? 0
            let variety: Double = sameKind >= 3 ? 0.7 : sameKind == 2 ? 0.85 : 1
            let photo: Double = candidate.thumbnailURL == nil ? 0.95 : 1
            let score = popularity * (0.35 + 0.65 * proximity) * taste * variety * photo
            return Suggestion(place: candidate, category: category, anchorName: nearest.name,
                              distance: distance, score: score)
        }
        return Array(suggestions.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Yeni sıralamada, bu pencerede eklenen yerler (✓) eski yerlerinde
    /// kalır: liste parmağın altında kaymaz.
    static func merge(_ fresh: [Suggestion], previous: [Suggestion], keeping kept: Set<String>) -> [Suggestion] {
        var merged = fresh.filter { !kept.contains($0.id) }
        for (index, item) in previous.enumerated() where kept.contains(item.id) {
            merged.insert(item, at: min(index, merged.count))
        }
        return merged
    }

    private static func shares(_ categories: [PlaceCategory]) -> [PlaceCategory: Double] {
        guard !categories.isEmpty else { return [:] }
        let counts = Dictionary(categories.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.mapValues { Double($0) / Double(categories.count) }
    }

    /// Günün yerlerinden en çok 6'sı (son eklenenler önce): her birinin
    /// çevresi aranır.
    static func anchors(_ day: [Place]) -> [Place] {
        Array(day.sorted { $0.addedAt > $1.addedAt }.prefix(6))
    }

    /// Günde yemek ya da kafe yoksa yakındaki popüler restoran ve kafeler de önerilir.
    static func needsFood(_ day: [Place]) -> Bool {
        !day.isEmpty && !day.contains { $0.category == .food || $0.category == .cafe }
    }

    /// Günün yerlerinin ortası.
    static func center(of places: [Place]) -> CLLocationCoordinate2D? {
        guard !places.isEmpty else { return nil }
        let count = Double(places.count)
        return CLLocationCoordinate2D(latitude: places.reduce(0) { $0 + $1.latitude } / count,
                                      longitude: places.reduce(0) { $0 + $1.longitude } / count)
    }
}

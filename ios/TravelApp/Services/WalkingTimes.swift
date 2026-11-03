import CoreLocation
import Foundation

/// Yerler arası gerçek yürüme süreleri (Geoapify Route Matrix, OpenStreetMap
/// yolları; Oguz'un 2026-11-03 kararı). Gün sırası, gün süresi ve "Yer
/// ekle"deki "yürüyerek n dk" bunlarla hesaplanır: Boğaz gibi suyu ya da
/// otoyolu aşan yerler kuş uçuşu yakın görünmez. Her iki nokta arası bir kez
/// sorulur ve telefonda saklanır (yürürken iki yön aynı sayılır). Anahtar
/// yoksa ya da günlük kredi dolduysa kuş uçuşu tahmin kullanılır.
@MainActor
final class WalkingTimes {
    static let shared = WalkingTimes()

    private let cache = DiskCache<WalkLeg>(name: "walking-times")
    /// Yolu bulunamayan çiftler (bu açılışta yeniden sorulmaz).
    private var noRoute: Set<String> = []
    /// Bir istekte en çok bu kadar nokta (Route Matrix en çok 1.000 hücre).
    private static let maxPoints = 30

    var isAvailable: Bool { GeoapifyService.isConfigured }

    /// Bilinen yürüme (sormadan).
    func walk(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> WalkLeg? {
        cache[Self.key(a, b)]
    }

    /// Noktaların her ikisi arasındaki eksik süreler tek istekte: eksik
    /// çiftlere dokunan en az sayıda nokta kaynak, hepsi hedef olur (güne
    /// yeni bir yer eklenince yalnızca onun satırı sorulur).
    func load(_ points: [CLLocationCoordinate2D]) async {
        let unique = Array(Self.unique(points).prefix(Self.maxPoints))
        var missing: [(Int, Int)] = []
        for i in unique.indices {
            for j in unique.indices where i < j && isMissing(unique[i], unique[j]) { missing.append((i, j)) }
        }
        let sources = Self.cover(missing).map { unique[$0] }
        await fetch(sources: sources, targets: unique)
    }

    /// `sources`taki noktalardan `targets`taki noktalara eksik süreler.
    func load(from sources: [CLLocationCoordinate2D], to targets: [CLLocationCoordinate2D]) async {
        let ends = Array(Self.unique(targets).prefix(10))
        let starts = Array(Self.unique(sources).prefix(Self.maxPoints)).filter { source in
            ends.contains { isMissing(source, $0) }
        }
        let needed = ends.filter { target in starts.contains { isMissing($0, target) } }
        await fetch(sources: starts, targets: needed)
    }

    /// Gün planı için yerler arası bilinen süreler (dakika).
    func table(for places: [Place]) -> DayPlanner.Walks {
        var walks = DayPlanner.Walks()
        for a in places {
            for b in places where a.id != b.id {
                if let leg = walk(a.coordinate, b.coordinate) {
                    walks.minutes[DayPlanner.Walks.Leg(from: a.id, to: b.id)] = leg.minutes
                }
            }
        }
        return walks
    }

    private func isMissing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        let key = Self.key(a, b)
        return Self.pointKey(a) != Self.pointKey(b) && cache[key] == nil && !noRoute.contains(key)
    }

    private func fetch(sources: [CLLocationCoordinate2D], targets: [CLLocationCoordinate2D]) async {
        guard !sources.isEmpty, !targets.isEmpty,
              let matrix = await GeoapifyService.shared.walkingMatrix(sources: sources, targets: targets) else { return }
        var found: [String: WalkLeg] = [:]
        for (i, source) in sources.enumerated() {
            for (j, target) in targets.enumerated() where Self.pointKey(source) != Self.pointKey(target) {
                let key = Self.key(source, target)
                if let leg = matrix[i][j] { found[key] = leg } else { noRoute.insert(key) }
            }
        }
        cache.merge(found)
    }

    // MARK: - Yardımcılar

    nonisolated static func pointKey(_ point: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", point.latitude, point.longitude)
    }

    /// İki yön için aynı anahtar.
    nonisolated static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        [pointKey(a), pointKey(b)].sorted().joined(separator: ">")
    }

    nonisolated static func unique(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var seen: Set<String> = []
        return points.filter { seen.insert(pointKey($0)).inserted }
    }

    /// Eksik çiftlerin hepsine dokunan az sayıda nokta (en çok çifte
    /// dokunan önce; eşitlikte küçük sıra).
    nonisolated static func cover(_ pairs: [(Int, Int)]) -> [Int] {
        var remaining = pairs
        var chosen: [Int] = []
        while !remaining.isEmpty {
            var counts: [Int: Int] = [:]
            for (a, b) in remaining {
                counts[a, default: 0] += 1
                counts[b, default: 0] += 1
            }
            guard let best = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key
            else { break }
            chosen.append(best)
            remaining.removeAll { $0.0 == best || $0.1 == best }
        }
        return chosen.sorted()
    }
}

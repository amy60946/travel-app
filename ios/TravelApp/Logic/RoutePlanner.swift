import Foundation

/// Yerleri günlere böler ve her günü yürüme sırasına dizer.
///
/// 1. Kapasiteyi aşan yerler (gün × günlük sınır) en sondan bırakılır.
/// 2. Yakın yerler aynı güne düşsün diye k-ortalama ile gruplanır.
/// 3. Dolu günlerden taşan yerler en yakın boş güne aktarılır.
/// 4. Günler ve gün içindeki duraklar en-yakın-komşu sırasıyla dizilir.
enum RoutePlanner {
    struct Point: Equatable {
        let id: UUID
        let latitude: Double
        let longitude: Double
    }

    struct Plan: Equatable {
        /// Her gün için durakların sırası.
        var days: [[UUID]]
        /// Kapasiteye sığmadığı için dışarıda kalanlar.
        var leftOver: [UUID]
    }

    static func plan(_ points: [Point], days dayCount: Int, maxPerDay: Int) -> Plan {
        guard dayCount > 0, maxPerDay > 0 else {
            return Plan(days: [], leftOver: points.map(\.id))
        }
        let capacity = dayCount * maxPerDay
        let kept = Array(points.prefix(capacity))
        let leftOver = points.dropFirst(capacity).map(\.id)
        guard !kept.isEmpty else {
            return Plan(days: Array(repeating: [], count: dayCount), leftOver: leftOver)
        }

        let k = min(dayCount, kept.count)
        var groups = balance(kMeans(kept, k: k), maxPerDay: maxPerDay)

        // Günleri birbirine yakın sırayla diz.
        groups = orderGroups(groups)
        var days = groups.map { nearestNeighborOrder($0).map(\.id) }
        while days.count < dayCount { days.append([]) }
        return Plan(days: days, leftOver: leftOver)
    }

    // MARK: - Mesafe

    /// Kısa mesafeler için yeterli düz yaklaşım (metre).
    static func distance(_ a: Point, _ b: Point) -> Double {
        let r = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let x = (b.longitude - a.longitude) * .pi / 180 * cos((lat1 + lat2) / 2)
        let y = lat2 - lat1
        return sqrt(x * x + y * y) * r
    }

    private static func centroid(_ points: [Point]) -> Point {
        let lat = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let lon = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return Point(id: UUID(), latitude: lat, longitude: lon)
    }

    // MARK: - Gruplama

    private static func kMeans(_ points: [Point], k: Int) -> [[Point]] {
        // Belirli (her seferinde aynı) başlangıç: en uzak nokta seçimi.
        var centers = [points[0]]
        while centers.count < k {
            let next = points.max { a, b in
                centers.map { distance($0, a) }.min()! < centers.map { distance($0, b) }.min()!
            }!
            centers.append(next)
        }

        var groups: [[Point]] = []
        for _ in 0..<20 {
            groups = Array(repeating: [], count: k)
            for p in points {
                let index = centers.indices.min { distance(centers[$0], p) < distance(centers[$1], p) }!
                groups[index].append(p)
            }
            let newCenters = groups.enumerated().map { i, g in g.isEmpty ? centers[i] : centroid(g) }
            if newCenters.map({ [$0.latitude, $0.longitude] }) == centers.map({ [$0.latitude, $0.longitude] }) {
                break
            }
            centers = newCenters
        }
        return groups
    }

    private static func balance(_ input: [[Point]], maxPerDay: Int) -> [[Point]] {
        var groups = input
        var moved = true
        while moved {
            moved = false
            for i in groups.indices where groups[i].count > maxPerDay {
                let center = centroid(groups[i])
                // Merkezden en uzak durağı, yeri olan en yakın güne taşı.
                guard let far = groups[i].max(by: { distance(center, $0) < distance(center, $1) }) else { continue }
                let target = groups.indices
                    .filter { $0 != i && groups[$0].count < maxPerDay }
                    .min { a, b in
                        distance(groups[a].isEmpty ? far : centroid(groups[a]), far)
                            < distance(groups[b].isEmpty ? far : centroid(groups[b]), far)
                    }
                guard let target else { continue }
                groups[i].removeAll { $0.id == far.id }
                groups[target].append(far)
                moved = true
            }
        }
        return groups
    }

    // MARK: - Sıralama

    private static func orderGroups(_ groups: [[Point]]) -> [[Point]] {
        let filled = groups.filter { !$0.isEmpty }
        guard filled.count > 1 else { return groups }
        let centers = filled.map(centroid)
        // En batıdaki günden başla, sonra en yakın güne geç.
        var remaining = Array(filled.indices)
        var order = [remaining.min { centers[$0].longitude < centers[$1].longitude }!]
        remaining.removeAll { $0 == order[0] }
        while !remaining.isEmpty {
            let last = centers[order.last!]
            let next = remaining.min { distance(last, centers[$0]) < distance(last, centers[$1]) }!
            order.append(next)
            remaining.removeAll { $0 == next }
        }
        return order.map { filled[$0] } + groups.filter(\.isEmpty)
    }

    static func nearestNeighborOrder(_ points: [Point]) -> [Point] {
        guard points.count > 2 else { return points }
        let center = centroid(points)
        // Merkezden en uzak uçtan başla ki rota geri dönmesin.
        var current = points.max { distance(center, $0) < distance(center, $1) }!
        var remaining = points.filter { $0.id != current.id }
        var result = [current]
        while !remaining.isEmpty {
            let next = remaining.min { distance(current, $0) < distance(current, $1) }!
            result.append(next)
            remaining.removeAll { $0.id == next.id }
            current = next
        }
        return result
    }
}

import Foundation

/// Günün saat tahmini ve "Akıllı sıra".
///
/// - Saat tahmini: gün 09:00'da başlar; her yere varış = önceki yerden
///   ayrılış + yürüme. Saati sabitlenen yere erken varılırsa o saate kadar
///   beklenir. Yürüme süresi Google'ın yürüyüş rotasından (biliniyorsa)
///   bacaklara mesafeye göre paylaştırılır; yoksa düz mesafe × 1,3, 80 m/dk.
/// - Akıllı sıra: müze ve tapınaklar sabah, yemek öğle (11:30–14:00) ve akşam
///   (18:00–21:00), manzara gün batımına doğru, alışveriş ve bar gün sonunda;
///   aynı zamanda az yürüme. Saati sabitlenen yere o saatte varılır.
///   Farklı başlangıçlarla birkaç sıra denenir, en iyi 3'ü önerilir.
enum DayPlanner {
    struct Stop: Equatable {
        let id: UUID
        let latitude: Double
        let longitude: Double
        let category: PlaceCategory
        /// Yerde geçirilecek süre (dakika).
        let visitMinutes: Int
        /// Sabitlenen saat (gece yarısından dakika).
        let pinned: Int?
    }

    /// Bir yerin tahmini varış saati ve (akıllı sırada) neden orada olduğu.
    struct Entry: Equatable {
        let id: UUID
        let arrival: Int
        let reason: Reason?
    }

    enum Reason: Equatable {
        case pinned, morning, lunch, dinner, sunset, evening
    }

    /// Günün başlangıcı: 09:00.
    static let dayStart = 9 * 60
    /// Yürüme hızı (m/dk) ve sokakların düz çizgiden uzunluğu.
    private static let metersPerMinute = 80.0
    private static let detour = 1.3

    // MARK: - Saat tahmini

    /// Sıradaki yerlere varış saatleri. `walkingMinutes`: Google'ın bu sıra
    /// için bulduğu toplam yürüme süresi (varsa bacaklara paylaştırılır).
    static func schedule(_ stops: [Stop], start: Int = DayPlanner.dayStart, walkingMinutes: Double? = nil) -> [Entry] {
        let legs = legMinutes(stops, total: walkingMinutes)
        var time = Double(start)
        var entries: [Entry] = []
        for (index, stop) in stops.enumerated() {
            if index > 0 { time += legs[index - 1] }
            if let pinned = stop.pinned, Double(pinned) > time { time = Double(pinned) }
            entries.append(Entry(id: stop.id, arrival: Int(time.rounded()), reason: reason(for: stop, arrival: Int(time))))
            time += Double(stop.visitMinutes)
        }
        return entries
    }

    /// Günün toplam süresi (dakika): ilk yere varıştan son yerden ayrılışa
    /// (yürüme, gezme ve sabit saate kadar bekleme).
    static func totalMinutes(_ stops: [Stop], walkingMinutes: Double? = nil) -> Int {
        guard let last = stops.last else { return 0 }
        let entries = schedule(stops, walkingMinutes: walkingMinutes)
        guard let end = entries.last?.arrival, let first = entries.first?.arrival else { return 0 }
        return end + last.visitMinutes - first
    }

    /// Bacakların yürüme süresi: Google toplamı düz mesafeye göre
    /// paylaştırılır; toplam yoksa düz mesafeden tahmin.
    static func legMinutes(_ stops: [Stop], total: Double? = nil) -> [Double] {
        let estimates = zip(stops, stops.dropFirst()).map { walk($0, $1) }
        guard let total, total > 0 else { return estimates }
        let sum = estimates.reduce(0, +)
        guard sum > 0 else { return estimates.map { _ in total / Double(max(estimates.count, 1)) } }
        return estimates.map { $0 / sum * total }
    }

    /// İki yer arası tahmini yürüme (dakika).
    static func walk(_ a: Stop, _ b: Stop) -> Double {
        walk(from: (a.latitude, a.longitude), to: b)
    }

    private static func walk(from a: (Double, Double), to b: Stop) -> Double {
        let r = 6_371_000.0
        let lat1 = a.0 * .pi / 180, lat2 = b.latitude * .pi / 180
        let x = (b.longitude - a.1) * .pi / 180 * cos((lat1 + lat2) / 2)
        let y = lat2 - lat1
        return sqrt(x * x + y * y) * r * detour / metersPerMinute
    }

    /// "09:00" gibi.
    static func clock(_ minutes: Int) -> String {
        let value = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// "4 sa 30 dk", "45 dk", "2 sa".
    static func durationText(_ minutes: Int) -> String {
        let rounded = Int((Double(minutes) / 5).rounded()) * 5
        let hours = rounded / 60, rest = rounded % 60
        if hours == 0 { return String(localized: "\(max(rest, 5)) dk") }
        if rest == 0 { return String(localized: "\(hours) sa") }
        return String(localized: "\(hours) sa \(rest) dk")
    }

    // MARK: - Akıllı sıra

    /// Önerilen sıralar (en iyisi önce, en çok `count`). `origin`: başlangıç
    /// noktası (ör. kullanıcının konumu); yoksa ilk yer saatine göre seçilir.
    static func smartOrders(_ stops: [Stop], origin: (latitude: Double, longitude: Double)? = nil,
                            start: Int = DayPlanner.dayStart, count: Int = 3) -> [[Stop]] {
        guard stops.count > 1 else { return stops.isEmpty ? [] : [stops] }
        var seen: Set<[UUID]> = []
        var results: [(order: [Stop], cost: Double)] = []
        let firsts: [Stop?] = [nil] + stops.filter { $0.pinned == nil }.map { Optional($0) }
        for weight in [1.0, 0.5, 2.0] {
            for first in firsts {
                let order = greedy(stops, origin: origin, first: first, weight: weight, start: start)
                let ids = order.map(\.id)
                guard !seen.contains(ids) else { continue }
                seen.insert(ids)
                results.append((order, cost(order, origin: origin, start: start)))
            }
        }
        return results.sorted { $0.cost < $1.cost }.prefix(count).map { $0.order }
    }

    /// Sıranın maliyeti: yürüme + saatine uymayan dakikalar + bekleme.
    static func cost(_ order: [Stop], origin: (latitude: Double, longitude: Double)? = nil,
                     start: Int = DayPlanner.dayStart) -> Double {
        var time = Double(start)
        var total = 0.0
        var previous: Stop?
        for stop in order {
            let travel = previous.map { walk($0, stop) } ?? origin.map { walk(from: ($0.latitude, $0.longitude), to: stop) } ?? 0
            time += travel
            total += travel
            if let pinned = stop.pinned {
                let gap = Double(pinned) - time
                // Geç kalmak beklemekten pahalı.
                total += gap >= 0 ? gap * 0.5 : -gap * 4
                time = max(time, Double(pinned))
            } else {
                total += penalty(stop.category, at: time)
            }
            time += Double(stop.visitMinutes)
            previous = stop
        }
        return total
    }

    private static func greedy(_ stops: [Stop], origin: (latitude: Double, longitude: Double)?, first: Stop?,
                               weight: Double, start: Int) -> [Stop] {
        var remaining = stops
        var order: [Stop] = []
        var time = Double(start)
        var position: (Double, Double)? = origin.map { ($0.latitude, $0.longitude) }

        func visit(_ stop: Stop) {
            let travel = position.map { walk(from: $0, to: stop) } ?? 0
            time += travel
            if let pinned = stop.pinned { time = max(time, Double(pinned)) }
            time += Double(stop.visitMinutes)
            position = (stop.latitude, stop.longitude)
            order.append(stop)
            remaining.removeAll { $0.id == stop.id }
        }

        if let first { visit(first) }
        while !remaining.isEmpty {
            // Saati en yakın sabit yer: ondan önce sığmayan yerlere gidilmez.
            let nextPinned = remaining.filter { $0.pinned != nil }.min { $0.pinned! < $1.pinned! }
            var best: (stop: Stop, score: Double)?
            for stop in remaining where stop.pinned == nil {
                let travel = position.map { walk(from: $0, to: stop) } ?? 0
                let arrival = time + travel
                let mismatch = penalty(stop.category, at: arrival)
                if let pinnedStop = nextPinned, let pinned = pinnedStop.pinned {
                    let leave = arrival + Double(stop.visitMinutes)
                    if leave + walk(stop, pinnedStop) > Double(pinned) + 10 { continue }
                    // Sabit saatli yerden sonrası bu yere daha uygunsa ertelenir
                    // (ör. manzara akşam yemeğinden sonra, gün batımına doğru).
                    let later = Double(pinned + pinnedStop.visitMinutes) + walk(pinnedStop, stop)
                    if penalty(stop.category, at: later) + 30 < mismatch { continue }
                }
                let score = travel + weight * mismatch
                if best == nil || score < best!.score { best = (stop, score) }
            }
            if let best {
                visit(best.stop)
            } else if let nextPinned {
                visit(nextPinned)
            } else {
                break
            }
        }
        return order
    }

    /// Türün tercih edilen saatleri (gece yarısından dakika).
    private static func windows(_ category: PlaceCategory) -> [ClosedRange<Double>] {
        switch category {
        case .museum: [570...1020]                  // 09:30–17:00
        case .temple: [480...720]                   // sabah
        case .park: [480...1080]
        case .food: [690...840, 1080...1260]        // öğle, akşam
        case .cafe: [600...1080]
        case .shopping: [840...1260]                // öğleden sonra, akşam
        case .viewpoint: [960...1230]               // gün batımına doğru
        case .bar: [1140...1560]                    // akşam
        case .hotel: [1200...1560]
        case .sight, .other: [480...1320]
        }
    }

    /// Saatine uymayan dakika (tercih edilen saatlerin dışında kalan).
    static func penalty(_ category: PlaceCategory, at time: Double) -> Double {
        windows(category).map { window in
            window.contains(time) ? 0 : min(abs(time - window.lowerBound), abs(time - window.upperBound))
        }.min() ?? 0
    }

    /// Yer bu saatte neden orada (yalnızca saatine uyuyorsa).
    private static func reason(for stop: Stop, arrival: Int) -> Reason? {
        if stop.pinned != nil { return .pinned }
        let time = Double(arrival)
        switch stop.category {
        case .museum, .temple: return time < 720 ? .morning : nil
        case .food: return (690...840).contains(time) ? .lunch : (1080...1260).contains(time) ? .dinner : nil
        case .viewpoint: return time >= 960 ? .sunset : nil
        case .shopping, .bar: return time >= 1020 ? .evening : nil
        default: return nil
        }
    }
}

extension Place {
    /// Gün planı için (saat sabitlenmişse onunla).
    func dayStop(pinned: Int?) -> DayPlanner.Stop {
        DayPlanner.Stop(id: id, latitude: latitude, longitude: longitude, category: category,
                        visitMinutes: visitDuration, pinned: pinned)
    }
}

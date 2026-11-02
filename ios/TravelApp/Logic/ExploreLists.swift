import Foundation

/// Keşfet'in bölümleri, ülkelerin Wikivoyage'da okunma sayılarından
/// (elle seçim yok):
/// - Popüler: son 30 günde en çok okunanlar.
/// - Bu ay yükselenler: en çok okunan 60 ülke içinde önceki 30 güne göre
///   ilgisi en çok artanlar.
/// - Gözden kaçanlar: ilk 20'nin dışında kalıp ilgisi artan ülkeler.
/// Bir ülke yalnızca bir bölümde görünür; "Senin için"deki ülkeler tekrar
/// edilmez.
enum ExploreLists {
    /// Bir sayfanın son 30 gün ve önceki 30 gündeki okunma sayısı.
    struct Interest: Codable, Hashable {
        var recent: Int
        var previous: Int

        /// İlgideki artış (1 = aynı, 2 = iki katı).
        var growth: Double { Double(recent) / Double(max(previous, 1)) }
    }

    struct Lists: Equatable {
        var popular: [Country] = []
        var trending: [Country] = []
        var underRadar: [Country] = []

        var isEmpty: Bool { popular.isEmpty && trending.isEmpty && underRadar.isEmpty }
        var all: [Country] { popular + trending + underRadar }
    }

    static func make(_ interest: [String: Interest], countries: [Country] = Country.all,
                     excluding shown: Set<String> = [], popularCount: Int = 10, trendingCount: Int = 6,
                     underRadarCount: Int = 10) -> Lists {
        let ranked = countries
            .compactMap { country in interest[country.title].map { (country: country, interest: $0) } }
            .filter { $0.interest.recent > 0 }
            .sorted { $0.interest.recent > $1.interest.recent }
        var used = shown
        var lists = Lists()

        lists.popular = ranked.filter { !used.contains($0.country.code) }.prefix(popularCount).map(\.country)
        used.formUnion(lists.popular.map(\.code))

        lists.trending = ranked.prefix(60)
            .filter { !used.contains($0.country.code) && $0.interest.previous > 0 }
            .sorted { $0.interest.growth > $1.interest.growth }
            .prefix(trendingCount)
            .map(\.country)
        used.formUnion(lists.trending.map(\.code))

        lists.underRadar = ranked.dropFirst(20).prefix(80)
            .filter { !used.contains($0.country.code) }
            .sorted { $0.interest.growth > $1.interest.growth }
            .prefix(underRadarCount)
            .map(\.country)
        return lists
    }

    /// Günlük okunma sayılarından (gün "2026-10-31" → sayı; veri yoksa nil)
    /// son 30 gün ve önceki günler.
    static func interest(daily: [String: Int?]) -> Interest {
        let days = daily.keys.sorted()
        let split = max(days.count - 30, 0)
        let sum = { (keys: ArraySlice<String>) in keys.reduce(0) { $0 + ((daily[$1] ?? nil) ?? 0) } }
        return Interest(recent: sum(days[split...]), previous: sum(days[..<split]))
    }
}

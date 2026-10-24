import SwiftUI

/// Gezi temposu. Durak sayıları docs/PLAN.md'deki başlangıç
/// varsayımlarıdır; kullanıcı testiyle ayarlanacak.
enum Pace: String, CaseIterable, Identifiable {
    case relaxed
    case normal
    case brisk

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .relaxed: "Rahat"
        case .normal: "Normal"
        case .brisk: "Tempolu"
        }
    }

    /// Günde kaç durak önerilir.
    var stopsPerDay: ClosedRange<Int> {
        switch self {
        case .relaxed: 3...4
        case .normal: 5...6
        case .brisk: 7...9
        }
    }

    func maxStops(days: Int) -> Int {
        max(days, 0) * stopsPerDay.upperBound
    }
}

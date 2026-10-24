import Foundation
import Network

/// Yürüyüşten önce bir şehrin anlatımlarını ve yürüyüş yollarını
/// telefona indirir. Harita karolarının kendisi Apple Haritalar'ın
/// "Çevrimdışı Haritalar" özelliğiyle indirilir.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var isOnExpensiveNetwork = false
    @Published var wifiOnly = UserDefaults.standard.object(forKey: "downloadWifiOnly") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wifiOnly, forKey: "downloadWifiOnly") }
    }

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            Task { @MainActor in self?.isOnExpensiveNetwork = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "TravelApp.network"))
    }

    deinit { monitor.cancel() }

    var blockedByNetwork: Bool { wifiOnly && isOnExpensiveNetwork }

    func downloadedAt(_ city: String) -> Date? {
        dates[city]
    }

    func download(city: String, store: AppStore) async {
        guard progress[city] == nil, !blockedByNetwork else { return }
        let days = store.dayPlan(for: city).days
        let places = days.flatMap { $0 }
        let total = Double(places.count + days.count)
        var done = 0.0
        progress[city] = 0

        for place in places {
            if let title = place.wikipediaTitle {
                _ = await WikipediaService.shared.summary(englishTitle: title)
            }
            done += 1
            progress[city] = done / max(total, 1)
        }
        for day in days {
            _ = await WalkingRoutes.route(through: day)
            done += 1
            progress[city] = done / max(total, 1)
        }

        var updated = dates
        updated[city] = Date()
        dates = updated
        progress[city] = nil
    }

    private var dates: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: "downloadDates") as? [String: Date] ?? [:] }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "downloadDates")
        }
    }
}

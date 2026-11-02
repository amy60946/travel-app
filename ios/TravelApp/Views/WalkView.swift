import MapKit
import SwiftUI

/// Yürü: harita açık; üstte sıradaki durak kartı (yol tarifi düğmesiyle);
/// yaklaşınca anlatım kendiliğinden başlar; altta küçük çalar ve "Sıradaki".
struct WalkView: View {
    /// Gezideki şehir (`Destination.id`).
    let stopID: UUID
    let dayIndex: Int
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var narrator = Narrator.shared
    @StateObject private var tracker = LocationTracker()
    @Environment(\.dismiss) private var dismiss

    @State private var mapFocus: MapFocus?
    /// Konum ilk bulununca harita bir kez oraya gider.
    @State private var centeredOnUser = false
    @State private var nextIndex = 0
    @State private var narrated: Set<UUID> = []
    @State private var route: WalkingRoutes.DayRoute?
    @State private var arrivedBanner: String?
    @State private var guidance: GuidanceDestination?

    /// Anlatımın başlama mesafesi (Tokyo testinde ayarlanacak).
    private let triggerMeters: CLLocationDistance = 50

    private var stops: [Place] {
        let days = store.dayPlan(stop: stopID)
        return days.indices.contains(dayIndex) ? days[dayIndex] : []
    }

    private var nextStop: Place? {
        stops.indices.contains(nextIndex) ? stops[nextIndex] : nil
    }

    var body: some View {
        ZStack {
            GoogleMap(focus: $mapFocus, markers: markers, lines: lines, showsGooglePlaces: false,
                      padding: EdgeInsets(top: 110, leading: 0, bottom: 90, trailing: 0))
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    CircleIconButton(systemImage: "xmark") { narrator.stop(); dismiss() }
                    directionCard
                }
                HStack {
                    Spacer()
                    CircleIconButton(systemImage: "location") { mapFocus = .user(zoom: 16) }
                        .accessibilityLabel(Text("Konumum"))
                }
                if let arrivedBanner {
                    Text(arrivedBanner)
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: Capsule())
                        .transition(.opacity)
                }
                Spacer()
                player
            }
            .padding(16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            tracker.start()
            mapFocus = .fitting(stops.map(\.coordinate), animated: false)
        }
        .onDisappear { tracker.stop() }
        .onReceive(tracker.$location) { location in
            guard let location else { return }
            if !centeredOnUser {
                centeredOnUser = true
                mapFocus = .point(location.coordinate, zoom: 16)
            }
            checkArrival(at: location)
        }
        .task { route = await WalkingRoutes.route(through: stops) }
        .fullScreenCover(item: $guidance) { GuidanceView(destination: $0) }
        .animation(.snappy, value: arrivedBanner)
    }

    /// Günün durakları (sıradaki siyah) ve aralarındaki yürüme yolu.
    private var markers: [GoogleMap.Marker] {
        stops.enumerated().map { index, place in
            GoogleMap.Marker(id: place.id.uuidString, coordinate: place.coordinate,
                             key: "\(place.name)|\(place.category.rawValue)|\(index == nextIndex)",
                             anchorsBottom: true, zIndex: index == nextIndex ? 1 : 0) {
                PlacePin(place: place, isActive: index == nextIndex).padding(6)
            }
        }
    }

    private var lines: [GoogleMap.Line] {
        (route?.lines ?? []).enumerated().map { index, line in
            GoogleMap.Line(id: "route-\(index)", coordinates: line, color: UIColor(Theme.accent))
        }
    }

    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let nextStop {
                Text("Sıradaki durak").font(Theme.caption).foregroundStyle(Theme.muted)
                Text(nextStop.name).font(Theme.headline)
                if let location = tracker.location {
                    Text(Measurement(value: location.distance(from: nextStop.location), unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road)))
                        .font(Theme.caption).foregroundStyle(Theme.muted)
                }
            } else {
                Text("Günün rotası bitti").font(Theme.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if let nextStop {
                DirectionsButton { guidance = GuidanceDestination(place: nextStop) }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .softShadow()
    }

    private var player: some View {
        HStack(spacing: 12) {
            Button { playNext() } label: {
                Image(systemName: narrator.isActive && !narrator.isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(narrator.currentTitle ?? nextStop?.name ?? "")
                    .font(Theme.font(15, .semibold)).lineLimit(1)
                Text(narrator.isActive ? LocalizedStringKey("Anlatım çalıyor") : LocalizedStringKey("Yaklaşınca anlatım kendiliğinden başlar"))
                    .font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Button {
                narrator.stop()
                nextIndex = min(nextIndex + 1, stops.count)
            } label: {
                Label("Sıradaki", systemImage: "forward.fill")
                    .font(Theme.font(13, .semibold))
            }
            .buttonStyle(.plain)
            .disabled(nextStop == nil)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .softShadow()
    }

    private func checkArrival(at location: CLLocation) {
        guard let stop = nextStop, !narrated.contains(stop.id),
              location.distance(from: stop.location) <= triggerMeters else { return }
        narrated.insert(stop.id)
        arrivedBanner = String(localized: "Yaklaştın, anlatım başladı")
        Task {
            await narrate(stop)
            try? await Task.sleep(for: .seconds(4))
            arrivedBanner = nil
        }
    }

    private func playNext() {
        if narrator.isActive {
            narrator.togglePause()
        } else if let stop = nextStop {
            narrated.insert(stop.id)
            Task { await narrate(stop) }
        }
    }

    private func narrate(_ stop: Place) async {
        guard let title = stop.wikipediaTitle,
              let summary = await WikipediaService.shared.summary(englishTitle: title) else {
            narrator.speak(stop.name, title: stop.name, language: WikipediaService.narrationLanguage)
            return
        }
        narrator.speak(summary.extract, title: stop.name, language: summary.language)
        // Anlatılan duraktan sonrakine geç.
        if let index = stops.firstIndex(of: stop), index == nextIndex {
            nextIndex = index + 1
        }
    }
}

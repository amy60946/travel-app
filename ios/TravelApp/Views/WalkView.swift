import MapKit
import SwiftUI

/// Yürü: harita açık; üstte sıradaki durak kartı; yaklaşınca anlatım
/// kendiliğinden başlar; altta küçük çalar ve "Sıradaki".
struct WalkView: View {
    let city: String
    let dayIndex: Int
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var narrator = Narrator.shared
    @StateObject private var tracker = LocationTracker()
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var nextIndex = 0
    @State private var narrated: Set<UUID> = []
    @State private var route: WalkingRoutes.DayRoute?
    @State private var arrivedBanner: String?

    /// Anlatımın başlama mesafesi (Tokyo testinde ayarlanacak).
    private let triggerMeters: CLLocationDistance = 50

    private var stops: [Place] {
        let days = store.dayPlan(for: city).days
        return days.indices.contains(dayIndex) ? days[dayIndex] : []
    }

    private var nextStop: Place? {
        stops.indices.contains(nextIndex) ? stops[nextIndex] : nil
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                        PlacePin(place: place, isActive: index == nextIndex)
                    }
                    .annotationTitles(.hidden)
                }
                if let route {
                    ForEach(Array(route.polylines.enumerated()), id: \.offset) { _, line in
                        MapPolyline(line).stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton() }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    CircleIconButton(systemImage: "xmark") { narrator.stop(); dismiss() }
                    directionCard
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
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
        .onReceive(tracker.$location) { location in
            if let location { checkArrival(at: location) }
        }
        .task { route = await WalkingRoutes.route(through: stops) }
        .animation(.snappy, value: arrivedBanner)
    }

    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let nextStop {
                Text("Sıradaki durak").font(Theme.caption).foregroundStyle(Theme.muted)
                Text(nextStop.name).font(Theme.headline)
                if let location = tracker.location {
                    Text("\(Int(location.distance(from: nextStop.location))) m")
                        .font(Theme.caption).foregroundStyle(Theme.muted)
                }
            } else {
                Text("Günün rotası bitti").font(Theme.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            narrator.speak(stop.name, title: stop.name, language: WikipediaService.preferredLanguage)
            return
        }
        narrator.speak(summary.extract, title: stop.name, language: summary.language)
        // Anlatılan duraktan sonrakine geç.
        if let index = stops.firstIndex(of: stop), index == nextIndex {
            nextIndex = index + 1
        }
    }
}

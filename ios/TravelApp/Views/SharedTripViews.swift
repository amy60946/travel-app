import MapKit
import SwiftUI

/// Keşfet'te "Gezginlerin rotaları": en yeni herkese açık geziler, yana
/// kayan kartlar. Sunucu yoksa ya da paylaşılan gezi yoksa görünmez.
struct SharedTripsSection: View {
    @Binding var path: [Route]
    @State private var trips: [SharedTrip] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !trips.isEmpty {
                SectionTitle("Gezginlerin rotaları")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(trips) { trip in
                            Button { path.append(.sharedTrip(trip.id)) } label: {
                                SharedTripCard(trip: trip).frame(width: 230)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .padding(.horizontal, -20)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 1, alignment: .leading)
        .task {
            guard Supabase.isConfigured else { return }
            let found = (try? await TripSharing.shared.publicTrips()) ?? []
            withAnimation(.snappy) { trips = found }
        }
    }
}

/// Paylaşılan gezi kartı: ilk şehrin fotoğrafı, bayraklar, başlık, kimin
/// gezisi ve kaç gün, kaç yer.
struct SharedTripCard: View {
    let trip: SharedTrip
    var height: CGFloat = 210

    var body: some View {
        CityPhoto(name: trip.cities.first ?? trip.title, englishTitle: trip.coverTitle)
            .frame(height: height)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: trip.title).font(Theme.font(19, .bold)).lineLimit(2)
                    Text(verbatim: trip.cities.joined(separator: " · "))
                        .font(Theme.font(12, .semibold))
                        .lineLimit(1)
                        .opacity(0.9)
                    HStack(spacing: 6) {
                        if let author = trip.author {
                            Text(verbatim: "\(author.emoji) \(author.name)").lineLimit(1)
                            Text(verbatim: "·")
                        }
                        Text(trip.summary).lineLimit(1)
                    }
                    .font(Theme.font(12, .semibold))
                    .opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                if !trip.flags.isEmpty {
                    Text(verbatim: trip.flags)
                        .font(.system(size: 14))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(.white, in: Capsule())
                        .padding(10)
                }
            }
    }
}

/// Keşfet aramasında "Geziler": başlığında, şehirlerinde ya da ülkesinde
/// aranan geçen paylaşılan geziler.
struct SharedTripResults: View {
    let query: String
    @Binding var path: [Route]
    @State private var trips: [SharedTrip] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !trips.isEmpty {
                SectionTitle("Gezginlerin rotaları")
                ForEach(trips) { trip in
                    Button { path.append(.sharedTrip(trip.id)) } label: {
                        ResultRow(title: trip.title, subtitle: subtitle(trip)) {
                            CityPhoto(name: trip.cities.first ?? trip.title, englishTitle: trip.coverTitle)
                        } trailing: {
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 1, alignment: .leading)
        .task(id: query) {
            guard Supabase.isConfigured else { return }
            // Yazarken her harfte değil, yazma durunca ara.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            trips = (try? await TripSharing.shared.publicTrips(matching: query, limit: 10)) ?? []
        }
    }

    private func subtitle(_ trip: SharedTrip) -> String {
        let author = trip.author.map { "\($0.emoji) \($0.name) · " } ?? ""
        return author + trip.cities.joined(separator: ", ") + " · " + trip.summary
    }
}

/// Paylaşılan gezi: haritada bütün yerler, şehir şehir ve gün gün liste,
/// kimin gezisi ve "Gezilerime kopyala" (Oguz, 2026-11-02).
struct SharedTripView: View {
    let tripID: UUID
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = Account.shared
    @Environment(\.dismiss) private var dismiss
    @State private var trip: SharedTrip?
    @State private var failed = false
    @State private var mapFocus: MapFocus?
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 400

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()
            HStack {
                CircleIconButton(systemImage: "chevron.left") { dismiss() }
                    .accessibilityLabel(Text("Geri"))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .slidingPanel(stops: [.height(150), .fraction(0.55), .belowTop(60)], selection: $panelStop,
                      onSettle: { panelHeight = $0 }) {
            header
        } content: {
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: tripID) { await load() }
    }

    private var spots: [(stop: SharedTrip.Payload.Stop, spot: SharedTrip.Payload.Spot)] {
        (trip?.data?.stops ?? []).flatMap { stop in stop.places.map { (stop, $0) } }
    }

    private var map: some View {
        let markers = spots.enumerated().map { index, item in
            GoogleMap.Marker(id: "shared-\(index)", coordinate: CLLocationCoordinate2D(latitude: item.spot.latitude,
                                                                                     longitude: item.spot.longitude),
                             key: "\(item.spot.category)") {
                CategoryPin(category: item.spot.placeCategory, size: 26)
            }
        }
        return GoogleMap(focus: $mapFocus, markers: markers,
                         padding: EdgeInsets(top: 52, leading: 0, bottom: panelHeight, trailing: 0))
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let trip {
                Text(verbatim: trip.title).font(Theme.font(22, .bold)).lineLimit(2)
                HStack(spacing: 8) {
                    if let author = trip.author {
                        Button { path.append(.traveler(trip.owner)) } label: {
                            HStack(spacing: 6) {
                                ProfileAvatar(emoji: author.emoji, size: 26)
                                Text(verbatim: author.name).font(Theme.font(14, .semibold)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        Text(verbatim: "·").foregroundStyle(Theme.muted)
                    }
                    Text(trip.summary).font(Theme.font(14)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            } else if failed {
                Text("Gezi açılamadı").font(Theme.font(20, .bold))
                Text("Paylaşım kaldırılmış olabilir ya da internet yok.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let trip, let payload = trip.data {
            VStack(alignment: .leading, spacing: 0) {
                if trip.owner == account.userID {
                    Label("Senin gezin", systemImage: "person.crop.circle")
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 8)
                } else {
                    PrimaryButton(title: "Gezilerime kopyala", systemImage: "square.on.square") { copy(trip) }
                        .padding(.vertical, 4)
                    Text("Şehirler, günler ve yerler gezilerine gelir; sonra istediğin gibi değiştirebilirsin.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 6)
                }
                let ranges = Journey.dayRanges(days: payload.stops.map(\.days))
                ForEach(Array(payload.stops.enumerated()), id: \.offset) { index, stop in
                    stopSection(stop, range: ranges[index])
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    private func stopSection(_ stop: SharedTrip.Payload.Stop, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CityPhoto(name: stop.city, englishTitle: stop.englishTitle)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: [stop.countryCode.map(Country.flag), stop.city].compactMap { $0 }.joined(separator: " "))
                        .font(Theme.font(19, .bold))
                    Text(verbatim: Journey.dayText(range)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.top, 22)
            .padding(.bottom, 4)
            ForEach(0..<max(stop.days, 1), id: \.self) { day in
                let spots = stop.places.filter { $0.day == day }
                if !spots.isEmpty {
                    Text("\(day + 1). gün")
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    VStack(spacing: 0) {
                        ForEach(spots) { spot in
                            Button { focus(spot) } label: {
                                HStack(spacing: 12) {
                                    CategoryIcon(category: spot.placeCategory, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: spot.name).font(Theme.font(16, .semibold)).lineLimit(2)
                                        Text(spot.placeCategory.title)
                                            .font(Theme.font(12, .bold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(spot.placeCategory.color)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private func load() async {
        do {
            trip = try await TripSharing.shared.trip(tripID)
            failed = trip == nil
        } catch {
            failed = true
        }
        let coordinates = spots.map { CLLocationCoordinate2D(latitude: $0.spot.latitude, longitude: $0.spot.longitude) }
        if let region = MKCoordinateRegion(fitting: coordinates, padding: 1.3) {
            mapFocus = .region(region, animated: false)
        }
    }

    private func focus(_ spot: SharedTrip.Payload.Spot) {
        mapFocus = .point(CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude), zoom: 15,
                          animated: true)
        panelStop = 0
    }

    private func copy(_ trip: SharedTrip) {
        guard let id = store.copySharedTrip(trip) else { return }
        path.append(.journey(id))
    }
}

/// Bir gezginin herkese açık gezileri (paylaşılan gezide adına dokununca).
struct TravelerView: View {
    let ownerID: UUID
    @Binding var path: [Route]
    @Environment(\.dismiss) private var dismiss
    @State private var trips: [SharedTrip]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CircleIconButton(systemImage: "chevron.left") { dismiss() }
                    .accessibilityLabel(Text("Geri"))
                    .padding(.top, 8)
                if let author = trips?.first?.author {
                    HStack(spacing: 14) {
                        ProfileAvatar(emoji: author.emoji, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: author.name).font(Theme.font(24, .bold))
                            Text("\(trips?.count ?? 0) gezi").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.top, 16)
                }
                if let trips {
                    if trips.isEmpty {
                        Text("Herkese açık gezisi yok.")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 24)
                    }
                    VStack(spacing: 14) {
                        ForEach(trips) { trip in
                            Button { path.append(.sharedTrip(trip.id)) } label: {
                                SharedTripCard(trip: trip, height: 190)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 20)
                } else {
                    ProgressView().padding(.top, 40).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: ownerID) {
            trips = (try? await TripSharing.shared.publicTrips(owner: ownerID, limit: 50)) ?? []
        }
    }
}

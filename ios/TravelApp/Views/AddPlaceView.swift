import MapKit
import SwiftUI

/// Yer ekle: arama (Apple Haritalar), Kayıtlarından, Popüler yerler
/// (Wikipedia okunma sayısı), Kendi yerini oluştur, Fotoğrafla ekle.
struct AddPlaceView: View {
    let city: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var popular: [WikipediaService.PopularPlace] = []
    @State private var popularFailed = false
    @State private var showCustom = false
    @State private var showCamera = false

    private var center: CLLocationCoordinate2D {
        store.cities.first { $0.name == city }?.coordinate
            ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
    }

    private var savedNotPlanned: [Place] {
        store.places(in: city).filter { !store.isPlanned($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showCustom = true } label: {
                        Label("Kendi yerini oluştur", systemImage: "mappin.and.ellipse")
                    }
                    Button { showCamera = true } label: {
                        Label("Fotoğrafla ekle", systemImage: "camera")
                    }
                }

                if !results.isEmpty {
                    Section("Arama sonuçları") {
                        ForEach(results, id: \.self) { item in
                            row(title: item.name ?? "", subtitle: item.placemark.title ?? "") {
                                addSearchResult(item)
                            }
                        }
                    }
                }

                if !savedNotPlanned.isEmpty {
                    Section("Kayıtlarından") {
                        ForEach(savedNotPlanned) { place in
                            row(title: place.name, subtitle: place.source.title) {
                                store.addToPlan([place.id], city: city)
                            }
                        }
                    }
                }

                Section {
                    if popular.isEmpty && !popularFailed {
                        ProgressView()
                    } else if popularFailed {
                        Text("Popüler yerler yüklenemedi. İnternet bağlantını kontrol et.")
                            .font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(popular) { item in
                        row(title: item.title, subtitle: String(localized: "Son 30 günde \(item.monthlyViews) okunma")) {
                            addPopular(item)
                        }
                    }
                } header: {
                    Text("Popüler yerler")
                } footer: {
                    Text("Sıralama: Wikipedia okunma sayısı. Arama: Apple Haritalar.")
                }
            }
            .searchable(text: $query, prompt: Text("\(city) içinde ara"))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Yer ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .task { await loadPopular() }
            .sheet(isPresented: $showCustom) { CustomPlaceView(city: city) }
            .sheet(isPresented: $showCamera) { CameraAddView() }
            .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 12) }
            .animation(.snappy, value: store.undoMessage)
        }
        .font(Theme.body)
    }

    private func row(title: String, subtitle: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, .semibold))
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Theme.hairline))
            }
            .buttonStyle(.plain)
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        results = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }

    private func loadPopular() async {
        do {
            popular = try await WikipediaService.shared.popularPlaces(latitude: center.latitude, longitude: center.longitude)
            popularFailed = popular.isEmpty
        } catch {
            popularFailed = true
        }
    }

    private func addSearchResult(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        store.add(Place(name: item.name ?? String(localized: "Yer"), city: city,
                        latitude: c.latitude, longitude: c.longitude,
                        category: PlaceCategory(item.pointOfInterestCategory), source: .search),
                  plan: true)
        results.removeAll { $0 == item }
    }

    private func addPopular(_ item: WikipediaService.PopularPlace) {
        store.add(Place(name: item.title, city: city, latitude: item.latitude, longitude: item.longitude,
                        category: .sight, source: .search, wikipediaTitle: item.title),
                  plan: true)
        popular.removeAll { $0.id == item.id }
    }
}

extension PlaceCategory {
    /// Apple Haritalar türünden bizim türümüze.
    init(_ category: MKPointOfInterestCategory?) {
        guard let category else {
            self = .sight
            return
        }
        switch category {
        case .museum: self = .museum
        case .restaurant, .bakery, .foodMarket, .brewery, .winery: self = .food
        case .cafe: self = .cafe
        case .store: self = .shopping
        case .park, .nationalPark, .beach: self = .park
        default: self = .sight
        }
    }
}

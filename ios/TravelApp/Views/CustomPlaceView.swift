import MapKit
import SwiftUI

/// Kendi yerin: ad, harita üstünde konum (harita kaydırılarak düzeltilir),
/// tür, not ve rotadaki günü.
struct CustomPlaceView: View {
    let city: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: PlaceCategory = .sight
    @State private var note = ""
    @State private var day: Int
    @State private var center: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic

    init(city: String, day: Int = 0) {
        self.city = city
        _day = State(initialValue: day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Yerin adı", text: $name)
                    Picker("Tür", selection: $category) {
                        ForEach(PlaceCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section {
                    Map(position: $position) { UserAnnotation() }
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .onMapCameraChange { center = $0.region.center }
                        .overlay {
                            Image(systemName: "mappin")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .offset(y: -16)
                                .allowsHitTesting(false)
                        }
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Konum")
                } footer: {
                    Text("Pini yerine oturtmak için haritayı kaydır.")
                }
                Section("Not") {
                    TextField("İsteğe bağlı", text: $note, axis: .vertical)
                }
                if store.trip(for: city).days > 1 {
                    Section {
                        Picker("Gün", selection: $day) {
                            ForEach(0..<store.trip(for: city).days, id: \.self) { Text("\($0 + 1). gün").tag($0) }
                        }
                    }
                }
            }
            .navigationTitle("Kendi yerin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || center == nil)
                }
            }
            .onAppear {
                let start = store.cities.first { $0.name == city }?.coordinate
                    ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
                position = .region(MKCoordinateRegion(center: start, latitudinalMeters: 3000, longitudinalMeters: 3000))
            }
        }
    }

    private func save() {
        guard let center else { return }
        store.add(Place(name: name.trimmingCharacters(in: .whitespaces), city: city,
                        latitude: center.latitude, longitude: center.longitude,
                        category: category, source: .manual, note: note),
                  plan: true, day: day)
        dismiss()
    }
}

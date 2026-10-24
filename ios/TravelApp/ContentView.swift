import SwiftUI

/// MVP ekranlarının iskeleti. Her sekme şimdilik yer tutucu; ekranlar
/// tasarım kesinleşince sırayla doldurulacak.
struct ContentView: View {
    var body: some View {
        TabView {
            PlaceholderScreen(title: "Gezim", systemImage: "map")
                .tabItem { Label("Gezim", systemImage: "map") }
            RoutePlannerScreen()
                .tabItem { Label("Rota", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            PlaceholderScreen(title: "Yürüyüş", systemImage: "figure.walk")
                .tabItem { Label("Yürüyüş", systemImage: "figure.walk") }
            PlaceholderScreen(title: "Kaydet", systemImage: "plus.circle")
                .tabItem { Label("Kaydet", systemImage: "plus.circle") }
        }
    }
}

struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("Yakında"))
                .navigationTitle(title)
        }
    }
}

/// Gün sayısı ve tempo seçimi (MVP kişiselleştirme).
struct RoutePlannerScreen: View {
    @State private var days = 3
    @State private var pace: Pace = .normal

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $days, in: 1...14) {
                    Text("\(days) gün")
                }
                Picker("Tempo", selection: $pace) {
                    ForEach(Pace.allCases) { pace in
                        Text(pace.title).tag(pace)
                    }
                }
                .pickerStyle(.segmented)
                Section {
                    Text("Günde \(pace.stopsPerDay.lowerBound)-\(pace.stopsPerDay.upperBound) durak")
                    Text("Toplam en fazla \(pace.maxStops(days: days)) durak")
                }
            }
            .navigationTitle("Rota")
        }
    }
}

#Preview {
    ContentView()
}

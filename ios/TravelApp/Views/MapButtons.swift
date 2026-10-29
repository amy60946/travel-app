import SwiftUI

/// Yürüyüş yol tarifi (uygulamanın içinde, GPS gibi): çerçeveli yuvarlak düğme.
struct DirectionsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Yol tarifi"))
    }
}

/// Harita türü seçimi (Standart / Uydu / Karma): beyaz yuvarlak düğme.
struct MapKindMenu: View {
    @Binding var selection: MapKind

    var body: some View {
        Menu {
            Picker("Harita türü", selection: $selection) {
                ForEach(MapKind.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: "map")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(.white, in: Circle())
                .softShadow()
        }
        .accessibilityLabel(Text("Harita türü"))
    }
}

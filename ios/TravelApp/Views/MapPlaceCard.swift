import SwiftUI

/// Haritada seçilen yerin alt kartı (Google Maps'teki gibi): türün
/// simgesi, ad, tür ve adres; altta düğmeler (Kaydet, Ayrıntılar, Yol tarifi).
struct MapPlaceCard<Actions: View>: View {
    let category: PlaceCategory
    let title: String
    let subtitle: String
    let onClose: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CategoryIcon(category: category, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.font(18, .semibold)).lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Kapat"))
            }
            HStack(spacing: 8) { actions }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.sheetRadius))
        .softShadow()
    }
}

/// Yürüyüş yol tarifi (Apple Haritalar'da açılır): çerçeveli yuvarlak düğme.
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

extension View {
    /// Alttaki sekme çubuğunun üstünde yüzen kart.
    func floatingAboveTabBar() -> some View {
        padding(.horizontal, 12).padding(.bottom, 76)
    }
}

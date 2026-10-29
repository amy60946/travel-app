import SwiftUI

/// Her türün haritadaki rengi: müze mor, kafe kahverengi, tapınak kırmızı…
/// Pinlere bakınca yerin ne olduğu bir bakışta anlaşılsın diye.
extension PlaceCategory {
    var color: Color {
        switch self {
        case .sight: Color(hex: 0xF2A100)
        case .temple: Color(hex: 0xE53935)
        case .museum: Color(hex: 0x8E24AA)
        case .food: Color(hex: 0xF57C00)
        case .cafe: Color(hex: 0x795548)
        case .shopping: Color(hex: 0xD81B60)
        case .park: Color(hex: 0x43A047)
        case .viewpoint: Color(hex: 0x039BE5)
        case .bar: Color(hex: 0x3949AB)
        case .hotel: Color(hex: 0x546E7A)
        case .other: Color(hex: 0x757575)
        }
    }
}

/// Türün renginde daire, içinde beyaz simge (listelerde ve kartlarda).
struct CategoryIcon: View {
    let category: PlaceCategory
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color, in: Circle())
            .accessibilityLabel(Text(category.title))
    }
}

/// Haritada yer pini: türün renginde daire, içinde türün beyaz simgesi
/// (Polarsteps'teki gibi). Müze mor, kafe kahverengi, tapınak kırmızı...
struct CategoryPin: View {
    let category: PlaceCategory
    var size: CGFloat = 30

    var body: some View {
        CategoryIcon(category: category, size: size)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .softShadow()
    }
}

/// Haritada kayıtlı yerlerin nasıl görüneceği (Ayarlar): türün simgesi ya da
/// yerin fotoğrafı.
enum PinStyle: String, CaseIterable, Identifiable {
    case icon, photo

    static let storageKey = "pinStyle"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .icon: "Simge"
        case .photo: "Fotoğraf"
        }
    }
}

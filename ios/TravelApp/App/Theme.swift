import SwiftUI

/// Tasarım dili (docs/URUN.md → Tasarım dili).
enum Theme {
    static let accent = Color(hex: 0xC94A2B)   // Kiremit: yalnızca rota ve ana düğme
    static let ink = Color(hex: 0x222222)
    static let muted = Color(hex: 0x6A6A6A)
    static let hairline = Color(hex: 0xDDDDDD)
    static let hairlineLight = Color(hex: 0xEBEBEB)
    static let surface = Color(hex: 0xF7F7F7)

    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 8
    static let sheetRadius: CGFloat = 24

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Figtree", size: size).weight(weight)
    }

    static let title = font(30, .bold)
    static let headline = font(17, .semibold)
    static let body = font(15)
    static let caption = font(13)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Tek kat, hafif gölge.
    func softShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

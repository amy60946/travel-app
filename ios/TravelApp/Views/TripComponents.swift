import SwiftUI

/// Alttan açılan pencerenin üstü: solda kapat, ortada başlık.
struct SheetHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(Theme.font(18, .bold))
            HStack {
                CircleIconButton(systemImage: "xmark", action: onClose)
                    .accessibilityLabel(Text("Kapat"))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

/// Gri zeminli arama alanı.
struct SearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var isSearching = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(prompt, text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if isSearching { ProgressView() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Temizle"))
            }
        }
        .font(Theme.font(16))
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// İnternetten fotoğraf; verilen alanı doldurur, taşanı kırpar.
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        Theme.surface
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Theme.surface
                    }
                }
            }
            .clipped()
    }
}

/// Şehrin fotoğrafı (Wikipedia, yoksa Wikivoyage); bulunamazsa şehirdeki
/// kayıtlı bir yerin fotoğrafı ya da simge.
struct CityPhoto: View {
    let name: String
    var englishTitle: String?
    var cover: Place?
    @State private var url: URL?

    var body: some View {
        Theme.surface
            .overlay {
                if let url {
                    RemoteImage(url: url)
                } else if let cover {
                    PlaceThumbnail(place: cover, cornerRadius: 0)
                } else {
                    Image(systemName: "building.2")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted)
                }
            }
            .clipped()
            .task(id: name) {
                var title = englishTitle
                if title == nil { title = await DiscoverService.shared.englishTitle(for: name) }
                url = await DiscoverService.shared.photo(title ?? name)
            }
    }
}

/// Fotoğraflı kutu, altta karartma üstünde beyaz başlık (kıta, ülke).
struct PhotoTile: View {
    let url: URL?
    let title: String
    var subtitle: String?
    var placeholder: String?

    var body: some View {
        RemoteImage(url: url)
            .overlay {
                if url == nil, let placeholder {
                    Text(placeholder).font(.system(size: 44))
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.font(17, .bold)).lineLimit(2)
                    if let subtitle {
                        Text(subtitle).font(Theme.font(12, .semibold)).opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// Yuvarlak "+" düğmesi; eklenince siyah ✓.
struct AddCircleButton: View {
    let isAdded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isAdded ? "checkmark" : "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isAdded ? .white : Theme.ink)
                .frame(width: 40, height: 40)
                .background(isAdded ? Theme.ink : .white, in: Circle())
                .overlay(Circle().stroke(isAdded ? .clear : Theme.hairline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isAdded ? LocalizedStringKey("Eklendi") : LocalizedStringKey("Ekle")))
    }
}

/// Liste satırı: solda fotoğraf ya da simge, başlık, alt yazı, sağda ek.
struct ResultRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            leading
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(16, .semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Bölüm başlığı (Polarsteps gibi büyük ve kalın).
struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Theme.font(22, .bold))
            .padding(.top, 24)
            .padding(.bottom, 6)
    }
}

/// Tam genişlikte kiremit ana düğme (Devam, Ekle).
struct WideButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(.plain)
    }
}

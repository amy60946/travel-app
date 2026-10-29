import SwiftUI

/// Ayarlar: uygulamanın dili (Türkçe / English; varsayılan Türkçe, arayüzü,
/// Wikipedia içeriklerini ve sesli anlatımı belirler) ve haritada kayıtlı
/// yerlerin görünüşü (türün simgesi ya da yerin fotoğrafı).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.turkish.rawValue
    @AppStorage(PinStyle.storageKey) private var pinStyle = PinStyle.icon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Ayarlar") { dismiss() }

            Text("Dil")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { option in
                    Button { choose(option) } label: {
                        HStack {
                            Text(verbatim: option.nativeName).font(Theme.font(16, .semibold))
                            Spacer()
                            if option.rawValue == language {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if option != AppLanguage.allCases.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .padding(.horizontal, 16)

            Text("Arayüz, Wikipedia içerikleri ve sesli anlatım bu dilde olur.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text("Haritada yerler")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 6)

            Picker("Haritada yerler", selection: $pinStyle) {
                ForEach(PinStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            Text("Simge: türün renkli işareti. Fotoğraf: yerin kendi fotoğrafı, köşesinde türün simgesi.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer()
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.white)
        .presentationCornerRadius(Theme.sheetRadius)
    }

    private func choose(_ option: AppLanguage) {
        guard option.rawValue != language else { return dismiss() }
        dismiss()
        // Pencere kapanınca bütün ekranlar yeni dilde yeniden çizilir.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            AppLanguage.select(option)
            language = option.rawValue
        }
    }
}

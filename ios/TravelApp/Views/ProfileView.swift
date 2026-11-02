import SwiftUI

/// Profil sekmesi: özet (gezi, şehir, yer, koleksiyon sayısı), seyrek
/// kullanılanlar (bütün kayıtlar, indirilenler, veri aktarma) ve ayarlar
/// (dil, harita görünümü, haritada kayıtlı yerlerin görünüşü).
struct ProfileView: View {
    @Binding var path: [Route]
    @Binding var sheet: AddSheet?
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.turkish.rawValue
    @AppStorage(PinStyle.storageKey) private var pinStyle = PinStyle.icon
    @State private var showLayers = false
    @State private var showCredits = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Profil").font(Theme.title).padding(.top, 8)
                // Apple ile giriş ya da profil (ad, simge).
                AccountCard().padding(.top, 16)
                stats.padding(.top, 16)
                // Girişliyken: gezilerin herkese açık anahtarları.
                SharingSection(path: $path)

                sectionTitle("Kayıtlar")
                card {
                    row("Tüm kayıtlarım", systemImage: "bookmark", detail: "\(store.places.count)") {
                        path.append(.saved)
                    }
                    Divider().padding(.leading, 52)
                    row("İndirilenler", systemImage: "arrow.down.circle") { path.append(.downloads) }
                    Divider().padding(.leading, 52)
                    row("Veri aktar", systemImage: "square.and.arrow.down") { sheet = .importData }
                }

                sectionTitle("Dil")
                card {
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
                note("Arayüz, Wikipedia içerikleri ve sesli anlatım bu dilde olur.")

                sectionTitle("Harita")
                card {
                    row("Harita görünümü", systemImage: "square.3.layers.3d") { showLayers = true }
                }
                Picker("Haritada yerler", selection: $pinStyle) {
                    ForEach(PinStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                note("Simge: türün renkli işareti. Fotoğraf: yerin kendi fotoğrafı, köşesinde türün simgesi.")

                sectionTitle("Hakkında")
                card {
                    row("Kaynaklar ve lisanslar", systemImage: "doc.text") { showCredits = true }
                }
                // Girişliyken: çıkış ve hesabı silme.
                AccountActionsSection()
            }
            .padding(.horizontal, 20)
            // Altta yüzen sekme çubuğu son satırı örtmesin.
            .padding(.bottom, 120)
        }
        .background(.white)
        .sheet(isPresented: $showLayers) { MapLayersSheet() }
        .sheet(isPresented: $showCredits) { CreditsSheet() }
    }

    /// Gezi, şehir, yer ve koleksiyon sayıları; kare kutular.
    private var stats: some View {
        let cities = Set(store.journeys.flatMap(\.stops).map(\.city)).count
        return HStack(spacing: 10) {
            stat(store.journeys.count, "Geziler", systemImage: "suitcase")
            stat(cities, "Şehirler", systemImage: "building.2")
            stat(store.places.count, "Yerler", systemImage: "mappin.and.ellipse")
            stat(store.collections.count, "Koleksiyonlar", systemImage: "rectangle.stack")
        }
    }

    private func stat(_ count: Int, _ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(verbatim: "\(count)").font(Theme.font(22, .bold))
            Text(title).font(Theme.font(11, .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.leading, 4)
            .padding(.top, 28)
            .padding(.bottom, 6)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.font(13))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, detail: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22)
                Text(title).font(Theme.font(16, .semibold))
                Spacer()
                if let detail { Text(verbatim: detail).font(Theme.font(15)).foregroundStyle(Theme.muted) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Dil değişince bütün ekranlar yeni dilde yeniden çizilir.
    private func choose(_ option: AppLanguage) {
        guard option.rawValue != language else { return }
        AppLanguage.select(option)
        language = option.rawValue
    }
}

/// Uygulamadaki içeriklerin kaynakları ve lisansları. Ekranlardaki küçük
/// kaynak yazıları kaldırıldı (Oguz, 2026-11-02); zorunlu olanlar yerinde
/// kaldı (Wikipedia/Wikivoyage yazısının sonu, haritasız Google listesi,
/// fotoğrafın ⓘ düğmesi), hepsi burada da toplu durur.
private struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Kaynaklar ve lisanslar") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    credit("Google Maps", "Harita, yer arama, puanlar, yorumlar, saatler ve yol tarifi. © Google.")
                    credit("Wikipedia", "Yer bilgileri, popüler yerler ve sesli anlatım metinleri. CC BY-SA 4.0 lisansıyla; Türkçesi olmayan yazılar Türkçeye çevrilir.")
                    credit("Wikivoyage", "Şehir ve ülke rehberleri, şehir listeleri. CC BY-SA 4.0.")
                    credit("Wikimedia Commons", "Yer ve şehir fotoğrafları; her fotoğrafın sahibi ve lisansı fotoğraf tam ekrandayken ⓘ düğmesinde.")
                    credit("Apple", "Şehir arama, konaklama arama, şehirler arası araç süresi ve iPhone çevirisi.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
    }

    private func credit(_ title: String, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).font(Theme.font(16, .semibold))
            Text(text).font(Theme.font(14)).foregroundStyle(Theme.muted)
        }
    }
}

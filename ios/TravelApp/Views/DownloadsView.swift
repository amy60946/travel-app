import SwiftUI

/// İndirilenler: internetsiz yürüyüş için anlatımlar ve yürüyüş yolları.
struct DownloadsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var downloads = DownloadManager()

    private var cities: [AppStore.CitySummary] { store.cities.filter(\.hasTrip) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("İndirilenler").font(Theme.title)
                Text("Yürüyüşten önce anlatımları ve yürüyüş yollarını telefona indir; yolda internet olmasa da çalışır.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.muted)

                Toggle("Yalnızca Wi-Fi ile indir", isOn: $downloads.wifiOnly)
                    .font(Theme.font(15, .semibold))
                    .tint(Theme.accent)

                if downloads.blockedByNetwork {
                    Text("Şu an mobil veridesin. İndirmek için Wi-Fi'ye bağlan ya da üstteki ayarı kapat.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                }

                ForEach(cities) { city in
                    row(city)
                }
                if cities.isEmpty {
                    Text("Henüz planlı bir gezin yok.").font(Theme.body).foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Haritayı da indir", systemImage: "map")
                        .font(Theme.headline)
                    Text("Harita görüntüsü Apple Haritalar'dan gelir. İnternetsiz harita için: Apple Haritalar → sağ üstte profil resmin → Çevrimdışı Haritalar → Yeni Harita İndir → şehri seç.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    private func row(_ city: AppStore.CitySummary) -> some View {
        let plan = store.dayPlan(for: city.name)
        let stopCount = plan.days.reduce(0) { $0 + $1.count }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(city.name).font(Theme.headline)
                Text("\(plan.days.count) gün · \(stopCount) anlatım")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                if let date = downloads.downloadedAt(city.name) {
                    Text("İndirildi: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if let value = downloads.progress[city.name] {
                ProgressView(value: value).frame(width: 80)
            } else {
                SecondaryButton(title: downloads.downloadedAt(city.name) == nil ? "İndir" : "Güncelle",
                                systemImage: "arrow.down.circle") {
                    Task { await downloads.download(city: city.name, store: store) }
                }
                .disabled(downloads.blockedByNetwork)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.hairlineLight))
    }
}

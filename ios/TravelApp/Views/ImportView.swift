import SwiftUI
import UniformTypeIdentifiers

/// Veri aktar: Google Maps (Takeout) dosyası, Instagram/TikTok veri
/// dosyası, kopyalanan yazı ve link. Kazıma yok; yalnızca kullanıcının
/// verdiği dosya ve link okunur.
struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = PlaceImporter()
    @StateObject private var social = SocialImporter()

    @State private var showFilePicker = false
    @State private var pickingSocial = false
    @State private var resultText: String?
    @State private var notFound: [String] = []
    @State private var linkMessage: String?
    @State private var readingText = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Bilgisayarda ya da telefonda takeout.google.com adresine gir.")
                        Text("2. \"Tümünün seçimini kaldır\" de, sonra yalnızca **Haritalar (yerleriniz)** ve **Kaydedilenler**'i seç.")
                        Text("3. Dışa aktarımı oluştur, gelen e-postadaki dosyayı indir.")
                        Text("4. Dosyalar uygulamasında .zip'e dokunup aç; içindeki .json ve .csv dosyalarını burada seç.")
                    }
                    .font(Theme.font(14))
                    .padding(.vertical, 4)
                    Button {
                        pickingSocial = false
                        showFilePicker = true
                    } label: {
                        Label("Dosya seç", systemImage: "doc.badge.plus")
                    }
                    .disabled(isBusy)
                } header: {
                    Text("Google Maps listelerin")
                } footer: {
                    Text("Yıldızlı yerler, Favoriler, \"Gitmek istiyorum\" ve kendi listelerin. Koordinatı olmayan yerler Apple Haritalar'da aranır ve \"Tahmini\" diye işaretlenir.")
                }

                socialSection

                if let status = social.status {
                    Section {
                        if let progress = social.progress {
                            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                                Text(status)
                            }
                        } else if importer.progress == nil {
                            ProgressView(status)
                        }
                    }
                }

                if let progress = importer.progress {
                    Section {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                            Text("Yerler bulunuyor: \(progress.done) / \(progress.total)")
                        }
                    }
                }

                if let resultText {
                    Section("Sonuç") {
                        Text(resultText).font(Theme.headline)
                        ForEach(notFound, id: \.self) { name in
                            Label(name, systemImage: "questionmark.circle").foregroundStyle(Theme.muted)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await pasteText() }
                    } label: {
                        Label("Kopyaladığın yazıdan yer bul", systemImage: "text.quote")
                    }
                    .disabled(isBusy)
                    if readingText {
                        ProgressView("Yazıdaki yerler bulunuyor…")
                    }
                } header: {
                    Text("Yazı")
                } footer: {
                    if PlaceAI.isAvailable {
                        Text("Instagram ya da TikTok açıklaması, mesaj veya liste kopyala. Yazıdaki yerleri yapay zekâ bulur.")
                    } else {
                        Text("Her satır bir yer adı olarak aranır. Yapay zekâ anahtarı eklenince açıklamalardaki yerler de bulunur.")
                    }
                }

                Section {
                    Button {
                        Task { await pasteLink() }
                    } label: {
                        Label("Kopyaladığın linki ekle", systemImage: "link")
                    }
                    if let linkMessage {
                        Text(linkMessage).font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Link")
                } footer: {
                    Text("Google Maps'te yeri paylaş → Kopyala, sonra buraya dön.")
                }

            }
            .navigationTitle("Veri aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.json, .commaSeparatedText, .plainText, .html],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task {
                        if pickingSocial {
                            await importSocial(urls)
                        } else {
                            await importFiles(urls)
                        }
                    }
                }
            }
        }
        .font(Theme.body)
    }

    private var isBusy: Bool {
        importer.progress != nil || social.status != nil || readingText
    }

    private var socialSection: some View {
        Section {
            DisclosureGroup("Instagram'dan nasıl indirilir?") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Instagram'da profiline gir → sağ üstte ☰ → **Ayarlar ve hareketler** → en üstte **Meta Hesabı** (eski adı: Hesaplar Merkezi).")
                    Text("2. **Bilgilerin ve izinlerin** → **Bilgilerini dışa aktar** (bazı telefonlarda: Bilgilerini indir) → **Dışa aktarma oluştur**.")
                    Text("3. Instagram hesabını seç → **Cihaza aktar** → **Bilgileri özelleştir** → yalnızca **Kaydedilenler**.")
                    Text("4. Tarih aralığı: **Tüm zamanlar**, Biçim: **JSON** → **Dışa aktarmayı başlat**.")
                    Text("5. Hazır olunca gelen e-postadaki .zip'i indir, Dosyalar'da aç; **your_instagram_activity → saved** klasöründeki **saved_posts.json** ve **saved_collections.json** dosyalarını seç.")
                }
                .font(Theme.font(14))
                .padding(.vertical, 4)
            }
            DisclosureGroup("TikTok'tan nasıl indirilir?") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. TikTok'ta profiline gir → ☰ → **Ayarlar ve gizlilik** → **Hesap** → **Verilerini indir**.")
                    Text("2. Biçim: **JSON** → **Veri iste**.")
                    Text("3. Hazır olunca **Verileri indir** sekmesinden indir, Dosyalar'da .zip'i aç; **user_data_tiktok.json** dosyasını seç.")
                }
                .font(Theme.font(14))
                .padding(.vertical, 4)
            }
            Button {
                pickingSocial = true
                showFilePicker = true
            } label: {
                Label("Instagram / TikTok dosyası seç", systemImage: "doc.badge.plus")
            }
            .disabled(isBusy)
        } header: {
            Text("Instagram ve TikTok kayıtların")
        } footer: {
            if PlaceAI.isAvailable {
                Text("Dosyada yer bilgisi yok. TikTok açıklaması TikTok'un resmi servisinden okunur, yerleri yapay zekâ bulur. Bulunamayan gönderiler Kayıtlarım'daki \"Yeri belirle\" listesine girer.")
            } else {
                Text("Yapay zekâ anahtarı olmadan gönderiler Kayıtlarım'daki \"Yeri belirle\" listesine girer.")
            }
        }
    }

    private func importSocial(_ urls: [URL]) async {
        var byKey: [String: SocialExport.Post] = [:]
        var order: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            for post in SocialExport.parse(data: data, fileName: url.lastPathComponent) {
                let key = SocialExport.canonical(post.url)
                if var existing = byKey[key] {
                    // Aynı gönderi iki dosyada: koleksiyon ve hesap adını birleştir.
                    existing.collection = existing.collection ?? post.collection
                    existing.author = existing.author ?? post.author
                    byKey[key] = existing
                } else {
                    byKey[key] = post
                    order.append(key)
                }
            }
        }
        let posts = order.compactMap { byKey[$0] }
        let fresh = posts.filter { !store.isKnown($0) }
        notFound = []
        guard !fresh.isEmpty else {
            resultText = posts.isEmpty
                ? String(localized: "Bu dosyalarda kayıtlı gönderi bulunamadı.")
                : String(localized: "Bu gönderiler zaten aktarılmış.")
            return
        }
        let result = await social.resolve(fresh, knownCities: store.cities, importer: importer)
        let added = store.importPlaces(result.places)
        store.addPending(result.pending)
        resultText = String(localized: "\(added) yer eklendi · \(result.pending.count) gönderi \"Yeri belirle\" listesinde")
    }

    private func importFiles(_ urls: [URL]) async {
        var items: [TakeoutParser.Item] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                items += TakeoutParser.parse(data: data, fileName: url.lastPathComponent)
            }
        }
        guard !items.isEmpty else {
            resultText = String(localized: "Bu dosyalarda yer bulunamadı.")
            notFound = []
            return
        }
        let result = await importer.resolve(items, knownCities: store.cities)
        let added = store.importPlaces(result.added)
        resultText = String(localized: "\(added) yer eklendi · \(result.notFound.count) bulunamadı")
        notFound = result.notFound
    }

    private func pasteText() async {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            resultText = String(localized: "Panoda yazı yok.")
            notFound = []
            return
        }
        readingText = true
        defer { readingText = false }
        var found = PlaceAI.lines(in: text)
        if PlaceAI.isAvailable {
            found = await PlaceAI.places(inText: text)
        }
        guard !found.isEmpty else {
            resultText = String(localized: "Yazıda yer bulunamadı.")
            notFound = []
            return
        }
        let items = found.map {
            TakeoutParser.Item(name: $0.name, latitude: nil, longitude: nil, address: $0.city,
                               note: "", url: nil, source: .text)
        }
        let result = await importer.resolve(items, knownCities: store.cities)
        let added = store.importPlaces(result.added)
        resultText = String(localized: "\(added) yer eklendi · \(result.notFound.count) bulunamadı")
        notFound = result.notFound
    }

    private func pasteLink() async {
        guard var url = UIPasteboard.general.url
                ?? UIPasteboard.general.string.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        else {
            linkMessage = String(localized: "Panoda link yok.")
            return
        }
        // Kısa linki (maps.app.goo.gl) tam adrese çevir.
        if url.host?.contains("goo.gl") == true,
           let fetched = try? await URLSession.shared.data(from: url), let full = fetched.1.url {
            url = full
        }
        guard url.host?.contains("google") == true else {
            linkMessage = String(localized: "Şimdilik yalnızca Google Maps linkleri ekleniyor.")
            return
        }
        let name = TakeoutParser.placeName(fromMapsURL: url) ?? String(localized: "Yer")
        let c = TakeoutParser.coordinate(fromMapsURL: url)
        let item = TakeoutParser.Item(name: name, latitude: c?.latitude, longitude: c?.longitude,
                                      note: "", url: url, source: .googleMaps)
        let result = await importer.resolve([item], knownCities: store.cities)
        if let place = result.added.first, store.importPlaces([place]) > 0 {
            linkMessage = String(localized: "\(place.name) → \(place.city) eklendi")
        } else {
            linkMessage = String(localized: "Yer bulunamadı ya da zaten kayıtlı.")
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// Veri aktar: Google Maps (Takeout) dosyası, Instagram/TikTok veri
/// dosyası, kopyalanan yazı ve link. Kazıma yok; yalnızca kullanıcının
/// verdiği dosya ve link okunur.
struct ImportView: View {
    /// "Paylaş → TravelApp" ile gelen dosya; açılınca hemen aktarılır.
    var initialFile: URL?

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var importer = PlaceImporter()
    @StateObject private var social = SocialImporter()

    private enum PickerMode { case files, folder }

    @State private var showFilePicker = false
    @State private var pickerMode = PickerMode.files
    @State private var folderName: String?
    @State private var loading = false
    @State private var resultText: String?
    @State private var notFound: [String] = []
    @State private var linkMessage: String?
    @State private var readingText = false

    /// Açık aktarma ekranı sayısı: açıkken ana ekran ikinci bir tane açmasın.
    static var openCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Bilgisayarda ya da telefonda takeout.google.com adresine gir.")
                        Text("2. \"Tümünün seçimini kaldır\" de, sonra yalnızca **Haritalar (yerleriniz)** ve **Kaydedilenler**'i seç.")
                        Text("3. Dışa aktarımı oluştur, gelen e-postadaki dosyayı indir.")
                        Text("4. Gelen e-postadaki .zip'i indir ve burada seç; açmana gerek yok.")
                    }
                    .font(Theme.font(14))
                    .padding(.vertical, 4)
                    Button {
                        pick(.files)
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

                if loading {
                    Section { ProgressView("Dosya açılıyor…") }
                }

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
                          allowedContentTypes: pickerMode == .folder
                              ? [.folder]
                              : [.zip, .json, .commaSeparatedText, .plainText, .html],
                          allowsMultipleSelection: pickerMode == .files) { result in
                guard case .success(let urls) = result else { return }
                switch pickerMode {
                case .files:
                    Task { await importURLs(urls) }
                case .folder:
                    if let folder = urls.first, ExportFolder.link(folder) {
                        folderName = ExportFolder.folderName
                        Task { await checkFolder(manual: true) }
                    } else {
                        resultText = String(localized: "Klasör bağlanamadı. Dosyalar'da bir klasör seç.")
                    }
                }
            }
            .onAppear { Self.openCount += 1 }
            .onDisappear { Self.openCount -= 1 }
            .task {
                folderName = ExportFolder.folderName
                if let initialFile {
                    await importURLs([initialFile])
                    // "Paylaş" ile gelen kopya artık gerekmiyor.
                    if initialFile.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: initialFile) }
                } else {
                    await checkFolder(manual: false)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await checkFolder(manual: false) } }
            }
        }
        .font(Theme.body)
    }

    private var isBusy: Bool {
        loading || importer.progress != nil || social.status != nil || readingText
    }

    private func pick(_ mode: PickerMode) {
        pickerMode = mode
        showFilePicker = true
    }

    private var socialSection: some View {
        Section {
            Button {
                // Önce Instagram uygulaması; yüklü değilse tarayıcıdaki sayfa.
                openURL(ExportFiles.instagramAppSettings) { opened in
                    if !opened { openURL(ExportFiles.instagramExportPage) }
                }
            } label: {
                Label("Instagram'dan al", systemImage: "arrow.up.forward.app")
            }
            Text("Instagram'ın ayarları açılır: en üstte **Meta Hesabı** → **Bilgilerin ve izinlerin** → **Bilgilerini dışa aktar** → **Dışa aktarma oluştur**. Yalnızca **Kaydedilenler**'i ve **JSON**'u seç, başlat. Hazır olunca Instagram e-posta gönderir; bağlantıdan dosyayı indir.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
            Button {
                openURL(ExportFiles.instagramExportPage)
            } label: {
                Label("Tarayıcıda aç", systemImage: "safari")
            }
            .font(Theme.font(14))
            if folderName == nil {
                Button {
                    pick(.folder)
                } label: {
                    Label("İndirilenler klasörüne izin ver", systemImage: "folder.badge.plus")
                }
            } else {
                Button {
                    Task { await checkFolder(manual: true) }
                } label: {
                    Label("İndirilenleri şimdi kontrol et", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
            }
            Button {
                pick(.files)
            } label: {
                Label("Dosyayı kendim seçeyim", systemImage: "doc.badge.plus")
            }
            .disabled(isBusy)
            DisclosureGroup("Instagram'dan adım adım") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Instagram'da profiline gir → sağ üstte ☰ → **Ayarlar ve hareketler** → en üstte **Meta Hesabı** (eski adı: Hesaplar Merkezi).")
                    Text("2. **Bilgilerin ve izinlerin** → **Bilgilerini dışa aktar** (bazı telefonlarda: Bilgilerini indir) → **Dışa aktarma oluştur**.")
                    Text("3. Instagram hesabını seç → **Cihaza aktar** → **Bilgileri özelleştir** → yalnızca **Kaydedilenler**.")
                    Text("4. Tarih aralığı: **Tüm zamanlar**, Biçim: **JSON** → **Dışa aktarmayı başlat**.")
                    Text("5. Hazır olunca e-postadaki bağlantıdan .zip'i indir. Uygulama onu İndirilenler'de kendisi bulur ya da burada seçersin.")
                }
                .font(Theme.font(14))
                .padding(.vertical, 4)
            }
            DisclosureGroup("TikTok'tan nasıl indirilir?") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. TikTok'ta profiline gir → ☰ → **Ayarlar ve gizlilik** → **Hesap** → **Verilerini indir**.")
                    Text("2. Biçim: **JSON** → **Veri iste**.")
                    Text("3. Hazır olunca **Verileri indir** sekmesinden indir. Uygulama onu İndirilenler'de kendisi bulur ya da burada seçersin.")
                }
                .font(Theme.font(14))
                .padding(.vertical, 4)
            }
        } header: {
            Text("Instagram ve TikTok kayıtların")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let folderName {
                    Text("Bağlı klasör: \(folderName). İndirdiğin Instagram, TikTok ya da Google dosyasını uygulama kendisi bulup aktarır.")
                } else {
                    Text("Bir kez izin ver: açılan pencerede **İndirilenler** klasörünü seç. Sonra indirdiğin dosyayı uygulama kendisi bulup aktarır.")
                }
                if PlaceAI.isAvailable {
                    Text("Dosyada yer bilgisi yok. TikTok açıklaması TikTok'un resmi servisinden okunur, yerleri yapay zekâ bulur. Bulunamayan gönderiler Kayıtlarım'daki \"Yeri belirle\" listesine girer.")
                } else {
                    Text("Yapay zekâ anahtarı olmadan gönderiler Kayıtlarım'daki \"Yeri belirle\" listesine girer.")
                }
            }
        }
    }

    /// Seçilen ya da paylaşılan dosyaları açar (.zip dahil) ve aktarır.
    private func importURLs(_ urls: [URL]) async {
        loading = true
        let files = await Task.detached { ExportFiles.load(urls) }.value
        loading = false
        await importLoaded(files)
    }

    /// Bağlı klasörde yeni indirilmiş veri dosyası varsa kendiliğinden aktarır.
    private func checkFolder(manual: Bool) async {
        guard ExportFolder.isLinked, !isBusy else { return }
        loading = true
        let found = await Task.detached { ExportFolder.loadNewest() }.value
        loading = false
        guard let found else {
            if manual {
                resultText = String(localized: "İndirilenler'de yeni Instagram ya da TikTok dosyası yok.")
                notFound = []
            }
            return
        }
        await importLoaded(found.files)
        ExportFolder.markSeen(found)
        resultText = [String(localized: "\(found.name) bulundu ve aktarıldı"), resultText]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// Okunan dosyalardaki Instagram/TikTok gönderilerini ve Google Haritalar
    /// yerlerini aktarır.
    private func importLoaded(_ files: [ExportFiles.File]) async {
        notFound = []
        let posts = SocialExport.posts(in: files)
        var items: [TakeoutParser.Item] = []
        for file in files {
            items += TakeoutParser.parse(data: file.data, fileName: file.name)
        }
        guard !posts.isEmpty || !items.isEmpty else {
            resultText = String(localized: "Bu dosyalarda kayıtlı yer ya da gönderi bulunamadı.")
            return
        }
        var lines: [String] = []
        if !items.isEmpty {
            let result = await importer.resolve(items, knownCities: store.cities)
            let added = store.importPlaces(result.added)
            lines.append(String(localized: "\(added) yer eklendi · \(result.notFound.count) bulunamadı"))
            notFound = result.notFound
        }
        if !posts.isEmpty {
            let fresh = posts.filter { !store.isKnown($0) }
            if fresh.isEmpty {
                lines.append(String(localized: "Bu gönderiler zaten aktarılmış."))
            } else {
                let result = await social.resolve(fresh, knownCities: store.cities, importer: importer)
                let added = store.importPlaces(result.places)
                store.addPending(result.pending)
                lines.append(String(localized: "\(added) yer eklendi · \(result.pending.count) gönderi \"Yeri belirle\" listesinde"))
            }
        }
        resultText = lines.joined(separator: "\n")
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

import PhotosUI
import SwiftUI

/// "Yeri belirle": yeri kendiliğinden bulunamayan kayıtlı gönderiler.
/// Gönderi tek dokunuşla Instagram/TikTok'ta açılır. Ekran görüntüsü
/// alınırsa uygulama açıklamayı ve konum etiketini okuyup yeri bulur;
/// açıklama ya da konum adı kopyalanıp "Yapıştır" ile de bulunur.
struct PendingPostsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var importer = PlaceImporter()
    @StateObject private var social = SocialImporter()

    /// En son açılan gönderi; dönünce o andan sonraki ekran görüntüsü aranır.
    private struct Opened {
        let post: SocialExport.Post
        let date: Date
    }

    @State private var working: String?
    @State private var retrying = false
    @State private var message: String?
    @State private var opened: Opened?
    @State private var autoRead = Screenshots.canReadAutomatically
    @State private var pickingFor: SocialExport.Post?
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Gönderiyi aç, ekran görüntüsü al ve buraya dön: uygulama açıklamayı ve konum etiketini okuyup yeri ekler. Açıklamayı kopyalayıp Yapıştır'a da dokunabilirsin.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                    if !autoRead, PlaceAI.isAvailable, !store.pendingPosts.isEmpty {
                        SecondaryButton(title: "Ekran görüntülerini kendiliğinden oku", systemImage: "camera.viewfinder") {
                            Task { await askPhotoAccess() }
                        }
                    }
                    if PlaceAI.isAvailable, !store.pendingPosts.isEmpty {
                        SecondaryButton(title: "Yapay zekâyla yeniden ara", systemImage: "sparkles") {
                            Task { await retryAll() }
                        }
                        .disabled(retrying || working != nil)
                    }
                    if retrying {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(social.status ?? String(localized: "Aranıyor…"))
                                .font(Theme.font(14))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    if let message {
                        Text(message).font(Theme.font(14, .semibold))
                    }
                }
                ForEach(store.pendingPosts) { post in
                    row(post)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removePending(post)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                }
            }
            .overlay {
                if store.pendingPosts.isEmpty {
                    ContentUnavailableView("Yeri belirlenecek gönderi yok", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("Yeri belirle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .screenshots)
            .onChange(of: pickerItem) {
                guard let item = pickerItem, let post = pickingFor else { return }
                pickerItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read(image, for: post)
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, autoRead, let opened else { return }
                Task { await readNewScreenshot(after: opened) }
            }
        }
        .font(Theme.body)
    }

    private func row(_ post: SocialExport.Post) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(post.source.title)
                    .font(Theme.font(11, .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface, in: Capsule())
                Text(post.author.map { "@\($0)" } ?? String(localized: "Gönderi"))
                    .font(Theme.font(15, .semibold))
                    .lineLimit(1)
                Spacer()
                if let collection = post.collection {
                    Text(collection).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons(for: post) }
                VStack(alignment: .leading, spacing: 8) { buttons(for: post) }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func buttons(for post: SocialExport.Post) -> some View {
        SecondaryButton(title: "Aç", systemImage: "arrow.up.right") {
            opened = Opened(post: post, date: Date())
            openURL(post.url)
        }
        if PlaceAI.isAvailable {
            SecondaryButton(title: "Ekran görüntüsü", systemImage: "camera.viewfinder") {
                pickingFor = post
                showPicker = true
            }
        }
        SecondaryButton(title: "Yapıştır", systemImage: "doc.on.clipboard") {
            Task { await paste(for: post) }
        }
        if working == post.id { ProgressView() }
    }

    private func askPhotoAccess() async {
        autoRead = await Screenshots.requestAccess()
        if !autoRead {
            message = String(localized: "Fotoğraflar'a tam erişim verilmedi. Ekran görüntüsü düğmesiyle kendin seçebilirsin.")
        }
    }

    /// Gönderi açıldıktan sonra alınan ekran görüntüsü varsa okur.
    private func readNewScreenshot(after opened: Opened) async {
        guard working == nil, let image = await Screenshots.newest(after: opened.date) else { return }
        self.opened = nil
        await read(image, for: opened.post)
    }

    /// Listedeki bütün gönderiler için yapay zekâya yeniden sorar (ör. bir
    /// servis o an sınıra takıldıysa).
    private func retryAll() async {
        retrying = true
        defer { retrying = false }
        message = nil
        let result = await social.resolve(store.pendingPosts, knownCities: store.cities, importer: importer)
        let added = store.importPlaces(result.places)
        message = ([String(localized: "\(added) yer eklendi · \(result.pending.count) gönderi \"Yeri belirle\" listesinde")]
            + [result.summary].compactMap { $0 }).joined(separator: "\n")
    }

    /// Ekran görüntüsündeki konum etiketi, açıklama ve tabelalardan yeri bulur.
    private func read(_ image: UIImage, for post: SocialExport.Post) async {
        working = post.id
        defer { working = nil }
        let lines = await SignReader.readText(from: image)
        let found = await PlaceAI.places(inScreenshot: image, readText: lines, account: post.author)
        guard !found.isEmpty else {
            message = String(localized: "Ekran görüntüsünde yer bulunamadı. Konum etiketi ya da açıklama görünecek şekilde tekrar dene.")
            return
        }
        await add(found, for: post)
    }

    private func paste(for post: SocialExport.Post) async {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            message = String(localized: "Panoda yazı yok.")
            return
        }
        working = post.id
        defer { working = nil }

        var found: [PlaceAI.Found] = []
        if PlaceAI.isAvailable {
            found = await PlaceAI.places(inText: text)
        }
        // Kısa tek satır büyük ihtimalle kopyalanan konum adıdır.
        if found.isEmpty, text.count <= 60, !text.contains("\n") {
            found = [PlaceAI.Found(name: text)]
        }
        await add(found, for: post)
    }

    private func add(_ found: [PlaceAI.Found], for post: SocialExport.Post) async {
        let items = found.prefix(3).map { place in
            TakeoutParser.Item(name: place.name, latitude: nil, longitude: nil,
                               address: place.city ?? post.collection,
                               note: post.author.map { "@\($0)" } ?? "",
                               url: post.url, source: post.source)
        }
        let result = await importer.resolve(Array(items), knownCities: store.cities)
        guard !result.added.isEmpty else {
            message = String(localized: "Yer bulunamadı. Konum adını kopyalayıp tekrar dene.")
            return
        }
        store.importPlaces(result.added)
        store.removePending(post)
        message = String(localized: "\(result.added.map(\.name).joined(separator: ", ")) eklendi")
    }
}

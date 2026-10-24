import SwiftUI

/// "Yeri belirle": yeri kendiliğinden bulunamayan kayıtlı gönderiler.
/// Gönderi tek dokunuşla Instagram/TikTok'ta açılır; açıklama ya da konum
/// adı kopyalanıp "Yapıştır" ile yer bulunur.
struct PendingPostsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var importer = PlaceImporter()

    @State private var working: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Gönderiyi aç, açıklamayı ya da konum adını kopyala, buraya dönüp Yapıştır'a dokun.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
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
            HStack(spacing: 8) {
                SecondaryButton(title: "Aç", systemImage: "arrow.up.right") { openURL(post.url) }
                SecondaryButton(title: "Yapıştır", systemImage: "doc.on.clipboard") {
                    Task { await paste(for: post) }
                }
                if working == post.id { ProgressView() }
            }
        }
        .padding(.vertical, 4)
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

import SwiftUI

/// Fotoğraflar tam ekran: yana kaydırarak gezilir; aşağı ya da yukarı
/// itince (ya da çarpıya dokununca) kapanır. Wikimedia fotoğraflarında ⓘ
/// düğmesi fotoğrafın sahibini ve lisansını gösterir.
struct PhotoViewer: View {
    let photos: [URL]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var drag: CGFloat = 0
    @State private var showsCredit = false
    @State private var credits: [URL: WikipediaService.PhotoCredit] = [:]

    private var currentURL: URL? { photos.indices.contains(index) ? photos[index] : nil }
    private var isCommons: Bool { currentURL.flatMap(WikipediaService.commonsFileName) != nil }

    /// Çektikçe arka plan açılır (en çok %60).
    private var fade: Double { min(Double(abs(drag)) / 500, 0.6) }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - fade)
                .ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .offset(y: drag)
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        // Yalnızca dikey çekiş; yana kaydırma fotoğraf değiştirir.
                        if abs(value.translation.height) > abs(value.translation.width) {
                            drag = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if abs(drag) > 120 || abs(value.predictedEndTranslation.height) > 400 {
                            dismiss()
                        } else {
                            withAnimation(.snappy) { drag = 0 }
                        }
                    }
            )
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Kapat"))
            .padding(16)
            .opacity(drag == 0 ? 1 : 0)
        }
        .overlay(alignment: .bottomLeading) {
            if isCommons {
                VStack(alignment: .leading, spacing: 8) {
                    if showsCredit, let url = currentURL {
                        creditText(credits[url])
                    }
                    Button { withAnimation(.snappy) { showsCredit.toggle() } } label: {
                        Image(systemName: showsCredit ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Fotoğrafın sahibi ve lisansı"))
                }
                .padding(16)
                .padding(.bottom, photos.count > 1 ? 24 : 0)
                .opacity(drag == 0 ? 1 : 0)
            }
        }
        .task(id: showsCredit ? currentURL : nil) {
            guard showsCredit, let url = currentURL, credits[url] == nil else { return }
            if let found = await WikipediaService.shared.credit(for: url) { credits[url] = found }
        }
        .presentationBackground(.clear)
        .statusBarHidden()
    }

    @ViewBuilder
    private func creditText(_ credit: WikipediaService.PhotoCredit?) -> some View {
        Group {
            if let credit {
                let parts = [credit.author, credit.license].filter { !$0.isEmpty }
                if let page = credit.page {
                    Link(destination: page) { Text(verbatim: parts.joined(separator: " · ") + " · Wikimedia Commons") }
                } else {
                    Text(verbatim: parts.joined(separator: " · ") + " · Wikimedia Commons")
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .font(Theme.font(13))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 320, alignment: .leading)
    }
}

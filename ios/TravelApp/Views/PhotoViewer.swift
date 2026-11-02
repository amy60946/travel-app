import SwiftUI

/// Fotoğraf şeridi (Oguz, 31 Ekim): bir fotoğrafa dokununca o yerin
/// fotoğrafları hafifçe büyüyerek ekranın ortasında yana kayan bir şerit
/// olur; ortadaki büyük, kenardakiler küçülüp saydamlaşır. Parmakla
/// kaydırılır; boşluğa dokununca, aşağı ya da yukarı itince kapanır.
/// Wikimedia fotoğraflarında ⓘ düğmesi fotoğrafın sahibini ve lisansını gösterir.
struct PhotoViewer: View {
    let photos: [URL]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var position: Int?
    @State private var appeared = false
    @State private var drag: CGFloat = 0
    @State private var showsCredit = false
    @State private var credits: [URL: WikipediaService.PhotoCredit] = [:]

    /// Şeridi kayma animasyonu olmadan açar (şerit kendisi büyüyerek gelir).
    static func present(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private var currentIndex: Int { position ?? index }
    private var currentURL: URL? { photos.indices.contains(currentIndex) ? photos[currentIndex] : nil }
    private var isCommons: Bool { currentURL.flatMap(WikipediaService.commonsFileName) != nil }

    /// Çektikçe arka plan açılır.
    private var fade: Double { min(Double(abs(drag)) / 400, 1) }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.84, 520)
            ZStack {
                Color.black
                    .opacity((appeared ? 0.86 : 0) * (1 - fade * 0.7))
                    .ignoresSafeArea()
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { offset, url in
                            photo(url, width: width, maxHeight: proxy.size.height * 0.72)
                                .id(offset)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                        .opacity(phase.isIdentity ? 1 : 0.35)
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .frame(height: proxy.size.height)
                }
                .contentMargins(.horizontal, (proxy.size.width - width) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $position)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .offset(y: drag)
                // Boşluğa dokununca kapanır (fotoğrafa dokunmak kapatmaz).
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            // Yalnızca dikey çekiş; yana kaydırma fotoğraf değiştirir.
                            if abs(value.translation.height) > abs(value.translation.width) {
                                drag = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if abs(drag) > 110 || abs(value.predictedEndTranslation.height) > 380 {
                                close()
                            } else {
                                withAnimation(.snappy) { drag = 0 }
                            }
                        }
                )
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Kapat"))
            .padding(16)
            .opacity(appeared && drag == 0 ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            bottomBar.opacity(appeared && drag == 0 ? 1 : 0)
        }
        .task(id: showsCredit ? currentURL : nil) {
            guard showsCredit, let url = currentURL, credits[url] == nil else { return }
            if let found = await WikipediaService.shared.credit(for: url) { credits[url] = found }
        }
        .onAppear {
            position = index
            withAnimation(.spring(duration: 0.32, bounce: 0.18)) { appeared = true }
        }
        .presentationBackground(.clear)
        .statusBarHidden()
    }

    private func photo(_ url: URL, width: CGFloat, maxHeight: CGFloat) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } placeholder: {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.08))
                .frame(height: width * 0.75)
                .overlay { ProgressView().tint(.white) }
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight)
        // Fotoğrafa dokunmak şeridi kapatmasın.
        .onTapGesture {}
    }

    /// Altta: kaçıncı fotoğraf ve (Wikimedia'da) ⓘ ile sahibi ve lisansı.
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if showsCredit, isCommons, let url = currentURL {
                creditText(credits[url])
            }
            HStack {
                if isCommons {
                    Button { withAnimation(.snappy) { showsCredit.toggle() } } label: {
                        Image(systemName: showsCredit ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Fotoğrafın sahibi ve lisansı"))
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
                Spacer()
                if photos.count > 1 {
                    Text(verbatim: "\(currentIndex + 1) / \(photos.count)")
                        .font(Theme.font(14, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    /// Kapanırken şerit küçülüp kaybolur, sonra pencere kapanır.
    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            Self.present { dismiss() }
        }
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
        .frame(maxWidth: 320)
    }
}

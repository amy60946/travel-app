import SwiftUI

/// Fotoğraflar tam ekran: yana kaydırarak gezilir; aşağı ya da yukarı
/// itince (ya da çarpıya dokununca) kapanır.
struct PhotoViewer: View {
    let photos: [URL]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(drag) / 500, 0.6))
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
        .presentationBackground(.clear)
        .statusBarHidden()
    }
}

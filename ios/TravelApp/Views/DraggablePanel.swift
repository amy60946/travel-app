import SwiftUI

/// Alttaki panelin oturabileceği yükseklik.
enum PanelStop: Hashable {
    /// Sabit yükseklik (nokta).
    case height(CGFloat)
    /// Kullanılabilir yüksekliğin oranı.
    case fraction(CGFloat)
}

/// Haritanın üstünde alttan açılan, parmakla yukarı-aşağı sürüklenen panel
/// (Google Maps ve Polarsteps gibi). Bırakınca en yakın yüksekliğe oturur,
/// hızlı itince o yöndeki sıradakine geçer; tutamağa dokununca bir üst
/// yüksekliğe (en üstteyse en alta) geçer. Panel en üstte değilken liste
/// kaymaz, parmak paneli büyütür; en üstteyken liste kayar, üst kısmından
/// aşağı çekince panel küçülür.
struct DraggablePanel<Header: View, Content: View>: View {
    /// Küçükten büyüğe yükseklikler.
    let stops: [PanelStop]
    /// Panelin oturduğu yüksekliğin sırası (`stops` içinde).
    @Binding var selection: Int
    /// Panel bir yüksekliğe oturunca (haritanın görünen alanı için).
    var onSettle: (CGFloat) -> Void = { _ in }
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let heights = stops.map { height(of: $0, in: proxy.size.height) }
            let index = min(max(selection, 0), heights.count - 1)
            let isTallest = index == heights.count - 1
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    handle(isTallest: isTallest, index: index)
                    header()
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(heights: heights, index: index))

                ScrollView {
                    content()
                }
                .scrollDisabled(!isTallest)
                .scrollBounceBehavior(.basedOnSize)
                // Panel en üstte değilken listeyi sürüklemek paneli büyütür.
                .gesture(dragGesture(heights: heights, index: index), including: isTallest ? .subviews : .all)
            }
            .frame(height: shownHeight(heights[index] - drag, heights: heights), alignment: .top)
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius, topTrailingRadius: Theme.sheetRadius)
                    .fill(.white)
                    .ignoresSafeArea(edges: .bottom)
                    .softShadow()
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .onAppear { onSettle(heights[index]) }
            .onChange(of: heights[index]) { _, height in onSettle(height) }
        }
    }

    private func handle(isTallest: Bool, index: Int) -> some View {
        Button {
            withAnimation(.snappy) { selection = isTallest ? 0 : index + 1 }
        } label: {
            Capsule().fill(Theme.hairline)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isTallest ? Text("Paneli küçült") : Text("Paneli büyüt"))
    }

    private func dragGesture(heights: [CGFloat], index: Int) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                // Parmağın hızıyla gideceği yer: hızlı itiş bir sonrakine geçirir.
                let target = heights[index] - value.predictedEndTranslation.height
                let nearest = heights.indices.min { abs(heights[$0] - target) < abs(heights[$1] - target) } ?? index
                withAnimation(.snappy) { selection = nearest }
            }
    }

    private func height(of stop: PanelStop, in available: CGFloat) -> CGFloat {
        switch stop {
        case .height(let points): return min(points, available)
        case .fraction(let fraction): return available * fraction
        }
    }

    /// Sürüklerken en alt ve en üst yüksekliğin dışına az esneyerek çıkar.
    private func shownHeight(_ height: CGFloat, heights: [CGFloat]) -> CGFloat {
        guard let lowest = heights.min(), let highest = heights.max() else { return height }
        if height < lowest { return lowest - (lowest - height) * 0.25 }
        if height > highest { return highest + (height - highest) * 0.25 }
        return height
    }
}

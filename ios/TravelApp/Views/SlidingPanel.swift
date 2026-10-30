import FloatingPanel
import SwiftUI

/// Alttaki panelin oturabileceği yükseklik.
enum PanelStop: Hashable {
    /// Sabit yükseklik (nokta).
    case height(CGFloat)
    /// Kullanılabilir yüksekliğin oranı.
    case fraction(CGFloat)
}

extension View {
    /// Bu ekranın (haritanın) üstünde alttan açılan kayan panel; uygulamanın
    /// bütün panelleri bu (Tripadvisor ve Google Maps gibi). Panel parmağı
    /// birebir izler, bırakınca en yakın yüksekliğe oturur, hızlı itince o
    /// yöndeki sıradakine geçer; tutamağa dokununca bir üst yüksekliğe (en
    /// üstteyse en alta) geçer. Panel en üstte değilken listeyi kaydırmak
    /// paneli büyütür; en üstte liste kayar, liste başındayken aşağı çekince
    /// panel iner. Hazır FloatingPanel kütüphanesiyle (MIT, ücretsiz).
    ///
    /// - Parameters:
    ///   - stops: Küçükten büyüğe 2 ya da 3 yükseklik.
    ///   - selection: Panelin oturduğu yüksekliğin sırası.
    ///   - isHidden: Panel aşağı iner (ör. yer penceresi açıkken).
    ///   - onSettle: Panel bir yüksekliğe oturunca (haritanın görünen alanı için).
    func slidingPanel<Header: View, Content: View>(
        stops: [PanelStop], selection: Binding<Int>, isHidden: Bool = false,
        onSettle: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SlidingPanel(main: self, stops: stops, selection: selection, isHidden: isHidden, onSettle: onSettle,
                     header: header, content: content)
    }

    /// Panel ve altındaki ekran ayrı UIKit katmanlarında çizilir; uygulamanın
    /// ortak ayarları (veriler, dil, yazı tipi, renk) oraya kendiliğinden geçmez.
    func panelEnvironment(_ store: AppStore) -> some View {
        environmentObject(store)
            .environment(\.locale, AppLanguage.current.locale)
            .font(Theme.body)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
    }
}

private struct SlidingPanel<Main: View, Header: View, Content: View>: View {
    let main: Main
    let stops: [PanelStop]
    @Binding var selection: Int
    let isHidden: Bool
    let onSettle: (CGFloat) -> Void
    let header: () -> Header
    let content: () -> Content

    @EnvironmentObject private var store: AppStore
    @State private var layouts = PanelLayoutCache()
    /// Panelin yerleştiği alanın (ekranın güvenli alanı) yüksekliği.
    @State private var available: CGFloat = 0

    private var states: [FloatingPanelState] {
        switch stops.count {
        case 1: [.full]
        case 2: [.tip, .full]
        default: [.tip, .half, .full]
        }
    }

    private var index: Int { min(max(selection, 0), stops.count - 1) }

    /// Panelin oturduğu yükseklik (gizliyse 0).
    private var settledHeight: CGFloat {
        guard !isHidden, available > 0 else { return 0 }
        switch stops[index] {
        case .height(let points): return min(points, available)
        case .fraction(let fraction): return available * fraction
        }
    }

    var body: some View {
        let states = self.states
        main
            .panelEnvironment(store)
            .floatingPanel(coordinator: PanelCoordinator.self) { proxy in
                card(proxy: proxy, states: states)
                    .panelEnvironment(store)
            }
            .floatingPanelLayout(layouts.layout(stops: stops, states: states, initial: states[index]))
            .floatingPanelState(Binding(
                get: { isHidden ? FloatingPanelState.hidden : states[index] },
                set: { state in
                    // Parmakla taşınınca seçim de değişir.
                    guard let state, let found = states.firstIndex(of: state), found != selection else { return }
                    selection = found
                }))
            // Panelin kartı görünen kısmı kadar: alt köşeler hep görünür.
            .floatingPanelContentMode(.fitToBounds)
            .floatingPanelContentInsetAdjustmentBehavior(.never)
            .floatingPanelSurfaceAppearance(panelSurface)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
            } action: { available = $0 }
            .onAppear { onSettle(settledHeight) }
            .onChange(of: settledHeight) { _, height in onSettle(height) }
    }

    private func card(proxy: FloatingPanelProxy, states: [FloatingPanelState]) -> some View {
        VStack(spacing: 0) {
            handle(proxy: proxy, states: states)
            header()
            ScrollView {
                content()
            }
            .panelEnvironment(store)
            .floatingPanelScrollTracking(proxy: proxy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Kenarlardan ayrık, dört köşesi yuvarlak kart (alt köşeler ekranın
        // köşesiyle aynı kavisle).
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius + 4, bottomLeadingRadius: 44,
                                   bottomTrailingRadius: 44, topTrailingRadius: Theme.sheetRadius + 4,
                                   style: .continuous)
                .fill(.white)
                .softShadow()
                .padding(.bottom, 8)
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.horizontal, 8)
    }

    private func handle(proxy: FloatingPanelProxy, states: [FloatingPanelState]) -> some View {
        let isTallest = index == states.count - 1
        return Button {
            proxy.move(to: states[isTallest ? 0 : index + 1], animated: true)
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
}

/// Kartı SwiftUI çiziyor; kütüphanenin kendi yüzeyi saydam.
private let panelSurface: SurfaceAppearance = {
    let appearance = SurfaceAppearance()
    appearance.backgroundColor = .clear
    appearance.cornerRadius = 0
    appearance.shadows = []
    return appearance
}()

/// Panelin yükseklikleri. Kütüphane düzeni nesnenin kendisiyle karşılaştırır:
/// yükseklikler değişmedikçe aynı nesne verilir, yoksa panel her çizimde
/// yeniden yerleşir.
private final class PanelLayoutCache {
    private var stops: [PanelStop] = []
    private var cached: PanelLayout?

    func layout(stops: [PanelStop], states: [FloatingPanelState], initial: FloatingPanelState) -> PanelLayout {
        if let cached, stops == self.stops { return cached }
        let layout = PanelLayout(stops: stops, states: states, initial: initial)
        self.stops = stops
        cached = layout
        return layout
    }
}

private final class PanelLayout: NSObject, FloatingPanelLayout {
    let position: FloatingPanelPosition = .bottom
    let initialState: FloatingPanelState
    let anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring]

    init(stops: [PanelStop], states: [FloatingPanelState], initial: FloatingPanelState) {
        initialState = initial
        var anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] = [:]
        for (state, stop) in zip(states, stops) {
            switch stop {
            case .height(let points):
                anchors[state] = FloatingPanelLayoutAnchor(absoluteInset: points, edge: .bottom, referenceGuide: .safeArea)
            case .fraction(let fraction):
                anchors[state] = FloatingPanelLayoutAnchor(fractionalInset: fraction, edge: .bottom,
                                                           referenceGuide: .safeArea)
            }
        }
        self.anchors = anchors
    }

    func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint] {
        [surfaceView.leftAnchor.constraint(equalTo: view.leftAnchor),
         surfaceView.rightAnchor.constraint(equalTo: view.rightAnchor)]
    }

    /// Panel büyüyünce harita kararmaz.
    func backdropAlpha(for state: FloatingPanelState) -> CGFloat { 0 }
}

/// Paneli kurar; kütüphanenin kendi tutamağı gizli (bizimkine dokununca büyür).
private final class PanelCoordinator: FloatingPanelCoordinator {
    enum Event {}

    let proxy: FloatingPanelProxy

    init(action: @escaping (Event) -> Void) {
        proxy = FloatingPanelProxy(controller: FloatingPanelController())
    }

    func setupFloatingPanel<Main: View, Content: View>(mainHostingController: UIHostingController<Main>,
                                                       contentHostingController: UIHostingController<Content>) {
        contentHostingController.view.backgroundColor = .clear
        controller.surfaceView.grabberHandle.isHidden = true
        controller.set(contentViewController: contentHostingController)
        controller.addPanel(toParent: mainHostingController, animated: false)
    }

    func onUpdate<Representable>(context: UIViewControllerRepresentableContext<Representable>)
        where Representable: UIViewControllerRepresentable {}
}

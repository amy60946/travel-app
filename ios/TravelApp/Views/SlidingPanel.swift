import FloatingPanel
import SwiftUI

/// Alttaki panelin oturabileceği yükseklik.
enum PanelStop: Hashable {
    /// Sabit yükseklik (nokta).
    case height(CGFloat)
    /// Kullanılabilir yüksekliğin oranı.
    case fraction(CGFloat)
    /// En üst: panelin üstü güvenli alanın tepesinden bu kadar aşağıda
    /// (0: tam ekran; ekranın üst çubuğu görünsün diye ör. 60). Panel buraya
    /// çıkınca köşeleri düzleşir, harita tamamen kapanır (Google Maps'teki
    /// tam ekran liste gibi); aşağı çekince yine kart olur.
    case belowTop(CGFloat)
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
        case .belowTop(let inset): return max(available - inset, 0)
        }
    }

    /// Panel tam ekranda (en üst yükseklik `belowTop`): köşeler düz, gölge yok.
    private var isFullScreen: Bool {
        guard !isHidden, index == stops.count - 1, case .belowTop = stops[index] else { return false }
        return true
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
        let full = isFullScreen
        return VStack(spacing: 0) {
            handle(proxy: proxy, states: states)
            header()
            ScrollView {
                content()
            }
            .panelEnvironment(store)
            .floatingPanelScrollTracking(proxy: proxy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Ekranın iki kenarına ve en altına tam oturan kart; yalnızca üst
        // köşeler yuvarlak (Apple ve Google Haritalar gibi). Tam ekrana
        // çıkınca köşeler düzleşir.
        .background {
            UnevenRoundedRectangle(topLeadingRadius: full ? 0 : Theme.sheetRadius, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: full ? 0 : Theme.sheetRadius,
                                   style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(full ? 0 : 0.14), radius: 10, y: -1)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.snappy, value: full)
    }

    /// Tutamak: çevresi ferah (parmakla rahat tutulsun); dokununca bir üst
    /// yüksekliğe, en üstteyse en alta geçer.
    private func handle(proxy: FloatingPanelProxy, states: [FloatingPanelState]) -> some View {
        let isTallest = index == states.count - 1
        return Button {
            proxy.move(to: states[isTallest ? 0 : index + 1], animated: true)
        } label: {
            Capsule().fill(Theme.hairline)
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)
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
            case .belowTop(let inset):
                anchors[state] = FloatingPanelLayoutAnchor(absoluteInset: inset, edge: .top, referenceGuide: .safeArea)
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

/// Panelin üstündeki sekmeler (Gezilerim | Koleksiyonlar): geniş, seçili
/// olan siyah. Düğmeler SwiftUI'ın kendi düğmeleri; böylece sekmelerin
/// üstünden sürükleyince de panel hareket eder (sistemin bölümlü seçicisi
/// parmağı kendine alıyordu).
struct PanelTabs: View {
    let titles: [LocalizedStringKey]
    @Binding var selection: Int
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    withAnimation(.snappy) { selection = index }
                } label: {
                    Text(titles[index])
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(selection == index ? .white : Theme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if selection == index {
                                Capsule().fill(Theme.ink).matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
    }
}

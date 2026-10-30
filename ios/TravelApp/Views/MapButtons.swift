import CoreLocation
import SwiftUI

/// Yürüyüş yol tarifi (uygulamanın içinde, GPS gibi): çerçeveli yuvarlak düğme.
struct DirectionsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Yol tarifi"))
    }
}

/// Haritanın görünümü: her haritada aynı, seçim telefonda saklanır
/// (Google Maps'teki "Harita türü" ve "Harita ayrıntıları" gibi).
enum MapSettings {
    static let kindKey = "map.kind"
    static let trafficKey = "map.traffic"
    static let transitKey = "map.transit"
    static let tiltKey = "map.tilt3D"
    static let indoorKey = "map.indoor"
    /// Gizlenen Google yer türleri (virgülle ayrılmış).
    static let hiddenPlacesKey = "map.hiddenPlaces"

    static func hiddenLayers(_ stored: String) -> Set<GooglePlaceLayer> {
        Set(stored.split(separator: ",").compactMap { GooglePlaceLayer(rawValue: String($0)) })
    }

    static func store(_ layers: Set<GooglePlaceLayer>) -> String {
        GooglePlaceLayer.allCases.filter(layers.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Google haritasının görünüm kuralları: gizlenen yer türleri ve toplu
    /// taşıma. `showsPlaces` yanlışsa (ör. yürüyüş) Google'ın yer adları
    /// ve simgeleri hiç görünmez. Kural yoksa nil.
    static func style(showsPlaces: Bool, hidden: Set<GooglePlaceLayer>, transit: Bool) -> String? {
        var rules: [String] = []
        if showsPlaces {
            for layer in GooglePlaceLayer.allCases where hidden.contains(layer) {
                rules.append(#"{"featureType":"\#(layer.featureType)","elementType":"labels","stylers":[{"visibility":"off"}]}"#)
            }
        } else {
            rules.append(#"{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]}"#)
            rules.append(#"{"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}"#)
        }
        if !transit {
            rules.append(#"{"featureType":"transit","stylers":[{"visibility":"off"}]}"#)
        }
        return rules.isEmpty ? nil : "[" + rules.joined(separator: ",") + "]"
    }
}

/// Google'ın haritada gösterdiği yer türleri; her biri açılıp kapanır.
enum GooglePlaceLayer: String, CaseIterable, Identifiable {
    case attraction, business, park, worship, medical, school, government, sports

    var id: String { rawValue }

    var featureType: String {
        switch self {
        case .attraction: "poi.attraction"
        case .business: "poi.business"
        case .park: "poi.park"
        case .worship: "poi.place_of_worship"
        case .medical: "poi.medical"
        case .school: "poi.school"
        case .government: "poi.government"
        case .sports: "poi.sports_complex"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .attraction: "Gezilecek yerler"
        case .business: "Restoran, kafe, mağaza, otel"
        case .park: "Parklar"
        case .worship: "İbadet yerleri"
        case .medical: "Hastane, eczane"
        case .school: "Okullar"
        case .government: "Resmi binalar"
        case .sports: "Spor alanları"
        }
    }

    var systemImage: String {
        switch self {
        case .attraction: "camera"
        case .business: "fork.knife"
        case .park: "tree"
        case .worship: "building.columns"
        case .medical: "cross.case"
        case .school: "graduationcap"
        case .government: "building.2"
        case .sports: "figure.run"
        }
    }
}

/// Her haritanın sağ üstündeki düğmeler (hepsinde aynı): harita
/// görünümü (katmanlar) ve konumum.
struct MapControls: View {
    @Binding var focus: MapFocus?
    var zoom: Float = 15
    @State private var showLayers = false
    @State private var showLocationDenied = false
    @State private var locationManager = CLLocationManager()

    var body: some View {
        VStack(spacing: 10) {
            CircleIconButton(systemImage: "square.3.layers.3d") { showLayers = true }
                .accessibilityLabel(Text("Harita görünümü"))
            CircleIconButton(systemImage: "location", action: showMyLocation)
                .accessibilityLabel(Text("Konumum"))
        }
        .sheet(isPresented: $showLayers) { MapLayersSheet() }
        .task {
            #if DEBUG
            // `-screen layers`: harita görünümü penceresi açık (ekran görüntüsü için).
            if !Self.openedLaunchScreen, UserDefaults.standard.string(forKey: "screen") == "layers" {
                Self.openedLaunchScreen = true
                try? await Task.sleep(for: .seconds(1))
                showLayers = true
            }
            #endif
        }
        .alert("Konum izni kapalı", isPresented: $showLocationDenied) {
            Button("Ayarları aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Konumunu haritada görmek için Ayarlar'da Location → While Using the App seç.")
        }
    }

    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    private func showMyLocation() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDenied = true
        default:
            locationManager.requestWhenInUseAuthorization()
            focus = .user(zoom: zoom)
        }
    }
}

/// Harita görünümü penceresi (Google Maps'teki katmanlar gibi): harita
/// türü, ayrıntılar (trafik, toplu taşıma, 3B, bina içi), Google'ın yer
/// türleri ve kayıtlı yerlerin görünüşü. Seçim bütün haritalarda geçerli.
struct MapLayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MapSettings.kindKey) private var kind = MapKind.standard
    @AppStorage(MapSettings.trafficKey) private var traffic = false
    @AppStorage(MapSettings.transitKey) private var transit = true
    @AppStorage(MapSettings.tiltKey) private var tilt3D = false
    @AppStorage(MapSettings.indoorKey) private var indoor = false
    @AppStorage(MapSettings.hiddenPlacesKey) private var hiddenPlaces = ""
    @AppStorage(PinStyle.storageKey) private var pinStyle = PinStyle.icon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Harita görünümü") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    title("Harita türü")
                    HStack(spacing: 10) {
                        ForEach(MapKind.allCases) { option in
                            tile(option.title, systemImage: option.systemImage, isOn: kind == option) { kind = option }
                        }
                    }

                    title("Ayrıntılar")
                    HStack(spacing: 10) {
                        tile("Trafik", systemImage: "car", isOn: traffic) { traffic.toggle() }
                        tile("Toplu taşıma", systemImage: "tram", isOn: transit) { transit.toggle() }
                        tile("3B", systemImage: "view.3d", isOn: tilt3D) { tilt3D.toggle() }
                        tile("Bina içi", systemImage: "building", isOn: indoor) { indoor.toggle() }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        title("Google yerleri")
                        Spacer()
                        let hidden = MapSettings.hiddenLayers(hiddenPlaces)
                        Button(hidden.isEmpty ? LocalizedStringKey("Hepsini gizle") : LocalizedStringKey("Hepsini göster")) {
                            hiddenPlaces = hidden.isEmpty ? MapSettings.store(Set(GooglePlaceLayer.allCases)) : ""
                        }
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(Theme.accent)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(GooglePlaceLayer.allCases) { layer in
                            layerChip(layer)
                        }
                    }
                    Text("Haritada Google'ın yerlerine dokununca puanı, yorumları ve fotoğrafları açılır.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 8)

                    title("Kayıtlı yerlerim")
                    Picker("Kayıtlı yerlerim", selection: $pinStyle) {
                        ForEach(PinStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(.white)
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.sheetRadius)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.font(15, .bold))
            .padding(.top, 18)
            .padding(.bottom, 10)
    }

    /// Kare seçim kutusu: simge ve ad; seçiliyse koyu çerçeveli.
    private func tile(_ title: LocalizedStringKey, systemImage: String, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isOn ? Theme.ink.opacity(0.08) : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isOn ? Theme.ink : .clear, lineWidth: 2))
                Text(title)
                    .font(Theme.font(12, isOn ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Theme.ink : Theme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func layerChip(_ layer: GooglePlaceLayer) -> some View {
        var hidden = MapSettings.hiddenLayers(hiddenPlaces)
        let isOn = !hidden.contains(layer)
        return Button {
            if isOn { hidden.insert(layer) } else { hidden.remove(layer) }
            hiddenPlaces = MapSettings.store(hidden)
        } label: {
            Label(layer.title, systemImage: layer.systemImage)
                .font(Theme.font(14, .semibold))
                .foregroundStyle(isOn ? .white : Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOn ? Theme.ink : .white, in: Capsule())
                .overlay(Capsule().stroke(isOn ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Satıra sığdığı kadar yan yana, sığmayanı alt satıra dizer (etiketler için).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

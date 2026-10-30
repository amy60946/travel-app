import GoogleMaps
import MapKit
import SwiftUI

/// Haritanın nereye bakacağı. Her yeni değerde (yeni `id`) harita oraya
/// gider; kullanıcı haritayı kaydırınca değer değişmez.
struct MapFocus: Equatable {
    enum Target {
        case region(MKCoordinateRegion)
        case point(CLLocationCoordinate2D, zoom: Float)
        /// Konumum (biliniyorsa).
        case user(zoom: Float)
        /// Yol tarifi: konumu yürüme yönüne dönük, hafif eğik izler.
        case follow(CLLocation, zoom: Float)
    }

    var target: Target
    var animated: Bool
    private(set) var id = UUID()

    init(target: Target, animated: Bool = true) {
        self.target = target
        self.animated = animated
    }

    static func == (lhs: MapFocus, rhs: MapFocus) -> Bool { lhs.id == rhs.id }

    static func region(_ region: MKCoordinateRegion, animated: Bool = true) -> MapFocus {
        MapFocus(target: .region(region), animated: animated)
    }

    static func point(_ coordinate: CLLocationCoordinate2D, zoom: Float, animated: Bool = true) -> MapFocus {
        MapFocus(target: .point(coordinate, zoom: zoom), animated: animated)
    }

    static func user(zoom: Float = 15) -> MapFocus {
        MapFocus(target: .user(zoom: zoom))
    }

    /// Noktaları kenarlarda pay bırakarak kapsar; nokta yoksa nil.
    static func fitting(_ coordinates: [CLLocationCoordinate2D], animated: Bool = true) -> MapFocus? {
        MKCoordinateRegion(fitting: coordinates).map { .region($0, animated: animated) }
    }
}

/// Haritanın şu an gösterdiği alan (kaydırma bitince bildirilir).
struct MapViewport {
    var region: MKCoordinateRegion
    var zoom: Float

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        abs(coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && abs(coordinate.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
    }
}

/// Google Haritalar (Maps SDK for iOS; iPhone'da sınırsız ücretsiz).
/// Uygulamanın bütün haritaları bu: bizim pinlerimiz SwiftUI görünümünden
/// resme çevrilip konur, rotalar çizgi olarak çizilir. Google'ın kendi
/// yerlerine (restoran, müze...) dokununca `onPlaceTap` yerin Google
/// kimliğini verir. Konumum mavi nokta olarak görünür (izin varsa).
struct GoogleMap: UIViewRepresentable {
    struct Marker: Identifiable {
        var id: String
        var coordinate: CLLocationCoordinate2D
        /// İçerik değişince (seçildi, fotoğrafı geldi, gün değişti...)
        /// farklı olmalı; simge yalnızca o zaman yeniden çizilir.
        var key: String
        /// Pinin altında ad yazıyorsa pinin yüksekliği: konuma pinin
        /// ortası oturur. nil ise simgenin ortası (ya da altı) oturur.
        var pinHeight: CGFloat?
        var anchorsBottom: Bool
        var zIndex: Int32
        var content: AnyView
        var onTap: (() -> Void)?

        init<Content: View>(id: String, coordinate: CLLocationCoordinate2D, key: String,
                            pinHeight: CGFloat? = nil, anchorsBottom: Bool = false, zIndex: Int32 = 0,
                            onTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
            self.id = id
            self.coordinate = coordinate
            self.key = key
            self.pinHeight = pinHeight
            self.anchorsBottom = anchorsBottom
            self.zIndex = zIndex
            self.onTap = onTap
            self.content = AnyView(content())
        }
    }

    struct Line: Identifiable {
        var id: String
        var coordinates: [CLLocationCoordinate2D]
        var color: UIColor
        var width: CGFloat = 5
        var dashed = false
        /// Şehirler arası düz çizgi: dünyanın eğriliğini izler.
        var geodesic = false
    }

    @Binding var focus: MapFocus?
    var markers: [Marker] = []
    var lines: [Line] = []
    var kind: MapKind = .standard
    /// Google'ın kendi yerleri (restoran, müze...) görünsün ve dokunulsun mu?
    var showsGooglePlaces = true
    /// Haritanın üstünü/altını örten paneller: haritanın ortası ve Google
    /// yazısı görünen alana göre kayar.
    var padding = EdgeInsets()
    var minZoom: Float?
    var onPlaceTap: ((_ placeID: String, _ name: String, _ coordinate: CLLocationCoordinate2D) -> Void)?
    var onMapTap: (() -> Void)?
    var onCameraIdle: ((MapViewport) -> Void)?
    /// Kullanıcı haritayı parmağıyla kaydırmaya başladı.
    var onUserGesture: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: 30, longitude: 20, zoom: 1.5)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = false
        map.settings.compassButton = false
        // Döndürme ve eğme kapalı: kuzey hep yukarıda (Google Maps'in sade hali).
        map.settings.rotateGestures = false
        map.settings.tiltGestures = false
        map.settings.indoorPicker = false
        map.isIndoorEnabled = false
        if !GoogleAPI.isConfigured { Self.addMissingKeyNotice(to: map) }
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let type: GMSMapViewType = switch kind {
        case .standard: .normal
        case .satellite: .satellite
        case .hybrid: .hybrid
        }
        if map.mapType != type { map.mapType = type }
        if coordinator.showsGooglePlaces != showsGooglePlaces {
            coordinator.showsGooglePlaces = showsGooglePlaces
            map.mapStyle = showsGooglePlaces ? nil : try? GMSMapStyle(jsonString: Self.hiddenPlacesStyle)
        }
        let insets = UIEdgeInsets(top: padding.top, left: padding.leading, bottom: padding.bottom, right: padding.trailing)
        if map.padding != insets { map.padding = insets }
        if let minZoom, map.minZoom != minZoom { map.setMinZoom(minZoom, maxZoom: map.maxZoom) }
        coordinator.sync(markers, on: map)
        coordinator.sync(lines, on: map)
        coordinator.apply(focus, to: map)
    }

    /// Google'ın yer adları ve simgeleri gizli (planlama haritalarında
    /// yalnızca bizim pinler); parklar ve yollar görünür.
    private static let hiddenPlacesStyle = """
    [{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
     {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]
    """

    /// Anahtar girilmeden derlenen sürümde harita boş kalır; nedeni yazsın.
    private static func addMissingKeyNotice(to map: GMSMapView) {
        let label = PaddedLabel()
        label.text = String(localized: "Google Haritalar anahtarı henüz girilmedi")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: map.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: map.centerYAnchor),
        ])
    }

    private final class PaddedLabel: UILabel {
        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 24, height: size.height + 16)
        }
    }

    // MARK: - Koordinatör

    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMap
        var showsGooglePlaces = true
        private var markers: [String: PlacedMarker] = [:]
        private var lines: [String: (polyline: GMSPolyline, signature: String)] = [:]
        private var appliedFocus: UUID?
        private var attemptedFocus: UUID?
        private var pendingAttempts = 0

        private struct PlacedMarker {
            var marker: GMSMarker
            var key: String
        }

        init(parent: GoogleMap) {
            self.parent = parent
        }

        func sync(_ specs: [Marker], on map: GMSMapView) {
            var seen = Set<String>()
            for spec in specs {
                seen.insert(spec.id)
                if let placed = markers[spec.id] {
                    placed.marker.position = spec.coordinate
                    placed.marker.zIndex = spec.zIndex
                    if placed.key != spec.key {
                        render(spec, into: placed.marker, scale: map.traitCollection.displayScale)
                        markers[spec.id] = PlacedMarker(marker: placed.marker, key: spec.key)
                    }
                } else {
                    let marker = GMSMarker(position: spec.coordinate)
                    marker.userData = spec.id
                    marker.zIndex = spec.zIndex
                    marker.tracksViewChanges = false
                    render(spec, into: marker, scale: map.traitCollection.displayScale)
                    marker.map = map
                    markers[spec.id] = PlacedMarker(marker: marker, key: spec.key)
                }
            }
            for (id, placed) in markers where !seen.contains(id) {
                placed.marker.map = nil
                markers[id] = nil
            }
        }

        private func render(_ spec: Marker, into marker: GMSMarker, scale: CGFloat) {
            let renderer = ImageRenderer(content: spec.content)
            renderer.scale = max(scale, 2)
            // Pinin altındaki uzun ad en çok bu genişlikte, iki satıra bölünür.
            renderer.proposedSize = ProposedViewSize(width: 150, height: nil)
            guard let image = renderer.uiImage, image.size.height > 0 else { return }
            marker.icon = image
            let y: CGFloat
            if spec.anchorsBottom {
                y = 1
            } else if let pinHeight = spec.pinHeight {
                y = min(1, (pinHeight / 2) / image.size.height)
            } else {
                y = 0.5
            }
            marker.groundAnchor = CGPoint(x: 0.5, y: y)
        }

        func sync(_ specs: [Line], on map: GMSMapView) {
            var seen = Set<String>()
            for spec in specs {
                seen.insert(spec.id)
                let first = spec.coordinates.first
                let last = spec.coordinates.last
                let signature = "\(spec.coordinates.count)|\(first?.latitude ?? 0),\(first?.longitude ?? 0)|"
                    + "\(last?.latitude ?? 0),\(last?.longitude ?? 0)|\(spec.color)|\(spec.width)|\(spec.dashed)"
                if lines[spec.id]?.signature == signature { continue }
                lines[spec.id]?.polyline.map = nil
                let path = GMSMutablePath()
                for coordinate in spec.coordinates { path.add(coordinate) }
                let polyline = GMSPolyline(path: path)
                polyline.strokeColor = spec.color
                polyline.strokeWidth = spec.width
                polyline.geodesic = spec.geodesic
                if spec.dashed {
                    // Kesik çizgi: yaklaşık 40 parça.
                    let dash = max(GMSGeometryLength(path) / 40, 1)
                    polyline.spans = GMSStyleSpans(path, [GMSStrokeStyle.solidColor(spec.color), GMSStrokeStyle.solidColor(.clear)],
                                                   [NSNumber(value: dash), NSNumber(value: dash * 0.6)], .geodesic)
                }
                polyline.map = map
                lines[spec.id] = (polyline, signature)
            }
            for (id, line) in lines where !seen.contains(id) {
                line.polyline.map = nil
                lines[id] = nil
            }
        }

        func apply(_ focus: MapFocus?, to map: GMSMapView) {
            guard let focus, focus.id != appliedFocus else { return }
            if attemptedFocus != focus.id {
                attemptedFocus = focus.id
                pendingAttempts = 0
            }
            // Harita daha ekrana yerleşmediyse biraz sonra.
            guard map.bounds.width > 0, map.bounds.height > 0 else {
                retry(focus, on: map, after: .milliseconds(50))
                return
            }
            let update: GMSCameraUpdate
            switch focus.target {
            case .region(let region):
                let southWest = CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                       longitude: region.center.longitude - region.span.longitudeDelta / 2)
                let northEast = CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                       longitude: region.center.longitude + region.span.longitudeDelta / 2)
                update = GMSCameraUpdate.fit(GMSCoordinateBounds(coordinate: southWest, coordinate: northEast), withPadding: 0)
            case .point(let coordinate, let zoom):
                update = GMSCameraUpdate.setTarget(coordinate, zoom: zoom)
            case .user(let zoom):
                // Konum izni yeni verildiyse konum birkaç saniye içinde gelir.
                guard let location = map.myLocation else {
                    retry(focus, on: map, after: .milliseconds(250))
                    return
                }
                update = GMSCameraUpdate.setTarget(location.coordinate, zoom: zoom)
            case .follow(let location, let zoom):
                appliedFocus = focus.id
                let bearing = location.course >= 0 ? location.course : map.camera.bearing
                let camera = GMSCameraPosition(target: location.coordinate, zoom: zoom, bearing: bearing, viewingAngle: 35)
                if focus.animated { map.animate(to: camera) } else { map.camera = camera }
                return
            }
            appliedFocus = focus.id
            if focus.animated { map.animate(with: update) } else { map.moveCamera(update) }
        }

        /// Odak daha uygulanamadıysa biraz sonra yeniden dener (en çok 40 kez;
        /// bu arada yeni bir odak geldiyse vazgeçer).
        private func retry(_ focus: MapFocus, on map: GMSMapView, after delay: Duration) {
            guard pendingAttempts < 40 else { return }
            pendingAttempts += 1
            Task { [weak self, weak map] in
                try? await Task.sleep(for: delay)
                guard let self, let map, self.parent.focus?.id == focus.id else { return }
                self.apply(focus, to: map)
            }
        }

        // MARK: GMSMapViewDelegate

        // Google haritası bunları ana iş parçacığında çağırır.

        nonisolated func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            MainActor.assumeIsolated { () -> Bool in
                guard let id = marker.userData as? String,
                      let spec = parent.markers.first(where: { $0.id == id }) else { return false }
                spec.onTap?()
                return true
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String,
                                 location: CLLocationCoordinate2D) {
            MainActor.assumeIsolated { parent.onPlaceTap?(placeID, name, location) }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated { parent.onMapTap?() }
        }

        nonisolated func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            guard gesture else { return }
            MainActor.assumeIsolated { parent.onUserGesture?() }
        }

        nonisolated func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            MainActor.assumeIsolated {
                guard let onIdle = parent.onCameraIdle else { return }
                onIdle(Self.viewport(of: mapView, zoom: position.zoom))
            }
        }

        private static func viewport(of map: GMSMapView, zoom: Float) -> MapViewport {
            let bounds = GMSCoordinateBounds(region: map.projection.visibleRegion())
            let northEast = bounds.northEast
            let southWest = bounds.southWest
            var longitudeDelta = northEast.longitude - southWest.longitude
            if longitudeDelta < 0 { longitudeDelta += 360 }
            let center = CLLocationCoordinate2D(latitude: (northEast.latitude + southWest.latitude) / 2,
                                                longitude: southWest.longitude + longitudeDelta / 2)
            let span = MKCoordinateSpan(latitudeDelta: northEast.latitude - southWest.latitude, longitudeDelta: longitudeDelta)
            return MapViewport(region: MKCoordinateRegion(center: center, span: span), zoom: zoom)
        }
    }
}

/// Dokunulmayan küçük harita (yer sayfasında): bir noktaya bakar.
struct StaticGoogleMap: View {
    let center: CLLocationCoordinate2D
    var zoom: Float = 15
    var markers: [GoogleMap.Marker] = []
    @State private var focus: MapFocus?

    var body: some View {
        GoogleMap(focus: $focus, markers: markers, showsGooglePlaces: false)
            .allowsHitTesting(false)
            .onAppear { focus = .point(center, zoom: zoom, animated: false) }
    }
}

import MapKit
import UIKit
import Vision

/// Fotoğraftaki tabela yazısını iPhone'un kendi içinde okur (ücretsiz,
/// internetsiz) ve bu yazıyla yakındaki yeri Apple Haritalar'da arar.
enum SignReader {
    struct Candidate: Identifiable {
        var item: MKMapItem
        var distance: CLLocationDistance
        var id: ObjectIdentifier { ObjectIdentifier(item) }
    }

    /// Fotoğraftaki yazı satırları, en büyükten küçüğe (tabela adı genelde en büyüğü).
    static func readText(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US", "tr-TR"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            let observations = request.results ?? []
            return observations
                .sorted { $0.boundingBox.height > $1.boundingBox.height }
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
        }.value
    }

    /// Okunan yazılarla 1 km içinde arar; en fazla 3 aday. `keepOrder`
    /// açıksa sorgu sırası korunur (yapay zekânın en olası tahmini önde),
    /// değilse en yakından uzağa sıralanır.
    static func candidates(for lines: [String], near location: CLLocation, keepOrder: Bool = false) async -> [Candidate] {
        var found: [Candidate] = []
        for line in lines.prefix(4) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = line
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000)
            request.resultTypes = .pointOfInterest
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            for item in items {
                let itemLocation = CLLocation(latitude: item.placemark.coordinate.latitude,
                                              longitude: item.placemark.coordinate.longitude)
                let distance = itemLocation.distance(from: location)
                guard distance < 1000, !found.contains(where: { $0.item.name == item.name }) else { continue }
                found.append(Candidate(item: item, distance: distance))
            }
        }
        if keepOrder {
            return Array(found.prefix(3))
        }
        return Array(found.sorted { $0.distance < $1.distance }.prefix(3))
    }

    /// İki aday listesini birleştirir: ikisinde de olan yer öne geçer,
    /// sonra ilk listenin sırası gelir. En fazla 4 aday.
    static func merge(_ first: [Candidate], _ second: [Candidate]) -> [Candidate] {
        let secondNames = Set(second.compactMap { $0.item.name })
        var merged = first.filter { secondNames.contains($0.item.name ?? "") }
        for candidate in first + second where !merged.contains(where: { $0.item.name == candidate.item.name }) {
            merged.append(candidate)
        }
        return Array(merged.prefix(4))
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

import Foundation

/// Kullanıcının indirdiği veri dosyalarından yer çıkarır. İnternete
/// çıkmaz, kazıma yapmaz; yalnızca dosyanın içini okur.
///
/// Google Takeout:
/// - "Saved Places.json" (Yıldızlı yerler): GeoJSON, çoğunlukla koordinatlı.
/// - "Favorite places.csv", "Want to go.csv" ve özel listeler: CSV,
///   koordinatsız; başlık ve linkten bulunur.
enum TakeoutParser {
    struct Item: Equatable {
        var name: String
        var latitude: Double?
        var longitude: Double?
        var address: String?
        var note: String
        var url: URL?
        var source: PlaceSource

        var hasCoordinate: Bool { latitude != nil && longitude != nil }
    }

    static func parse(data: Data, fileName: String) -> [Item] {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".csv") {
            return parseCSV(String(decoding: data, as: UTF8.self))
        }
        return parseGeoJSON(data)
    }

    // MARK: - GeoJSON (Yıldızlı yerler)

    static func parseGeoJSON(_ data: Data) -> [Item] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        return features.compactMap { feature in
            let properties = feature["properties"] as? [String: Any] ?? [:]
            let location = properties["location"] as? [String: Any] ?? [:]
            let url = (properties["google_maps_url"] as? String).flatMap(URL.init(string:))
            let name = (location["name"] as? String)
                ?? (properties["Title"] as? String)
                ?? url.flatMap(placeName(fromMapsURL:))
            guard let name, !name.isEmpty else { return nil }

            var item = Item(name: name, address: location["address"] as? String,
                            note: properties["Comment"] as? String ?? "", url: url, source: .googleMaps)
            // Koordinat [boylam, enlem]; [0, 0] "bilinmiyor" demek.
            if let geometry = feature["geometry"] as? [String: Any],
               let coordinates = geometry["coordinates"] as? [Double], coordinates.count >= 2,
               !(coordinates[0] == 0 && coordinates[1] == 0) {
                item.longitude = coordinates[0]
                item.latitude = coordinates[1]
            } else if let url, let c = coordinate(fromMapsURL: url) {
                item.latitude = c.latitude
                item.longitude = c.longitude
            }
            return item
        }
    }

    // MARK: - CSV (Favoriler, Gitmek istiyorum, özel listeler)

    static func parseCSV(_ text: String) -> [Item] {
        let rows = csvRows(text)
        guard let headerIndex = rows.firstIndex(where: { $0.first?.lowercased() == "title" }) else { return [] }
        let header = rows[headerIndex].map { $0.lowercased() }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let titleColumn = column("title") ?? 0
        let urlColumn = column("url")
        let noteColumn = column("note")
        let commentColumn = column("comment")

        return rows[(headerIndex + 1)...].compactMap { row in
            func value(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let url = URL(string: value(urlColumn))
            var name = value(titleColumn)
            if name.isEmpty, let url { name = placeName(fromMapsURL: url) ?? "" }
            guard !name.isEmpty else { return nil }
            let note = [value(noteColumn), value(commentColumn)].filter { !$0.isEmpty }.joined(separator: " · ")
            var item = Item(name: name, note: note, url: url, source: .googleMaps)
            if let url, let c = coordinate(fromMapsURL: url) {
                item.latitude = c.latitude
                item.longitude = c.longitude
            }
            return item
        }
    }

    /// Tırnaklı alanları ve satır içi yeni satırları destekleyen CSV okuyucu.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n":
                row.append(field); field = ""
                rows.append(row); row = []
            case "\r": break
            default: field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    // MARK: - Google Maps linki

    /// Linkteki koordinat: "!3d35.71!4d139.79", "@35.71,139.79" ya da "q=35.71,139.79".
    static func coordinate(fromMapsURL url: URL) -> (latitude: Double, longitude: Double)? {
        let text = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let patterns = [
            #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#,
            #"@(-?\d+\.\d+),(-?\d+\.\d+)"#,
            #"[?&](?:q|query|ll)=(-?\d+\.\d+),\s*(-?\d+\.\d+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let latRange = Range(match.range(at: 1), in: text),
                  let lonRange = Range(match.range(at: 2), in: text),
                  let lat = Double(text[latRange]), let lon = Double(text[lonRange]),
                  abs(lat) <= 90, abs(lon) <= 180 else { continue }
            return (lat, lon)
        }
        return nil
    }

    /// ".../maps/place/Sens%C5%8D-ji/..." → "Sensō-ji".
    static func placeName(fromMapsURL url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "place"), parts.indices.contains(index + 1) else { return nil }
        let raw = parts[index + 1].replacingOccurrences(of: "+", with: " ")
        let name = raw.removingPercentEncoding ?? raw
        return name.hasPrefix("@") || name.isEmpty ? nil : name
    }
}

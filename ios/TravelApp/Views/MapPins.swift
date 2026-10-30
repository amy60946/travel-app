import SwiftUI

/// Harita pinlerindeki fotoğraflar. Google haritasına pin resim olarak
/// konduğu için fotoğraf önceden indirilip küçültülür; geldikçe pin
/// fotoğraflısıyla değişir. Uygulama açıkken bellekte kalır.
@MainActor
final class PinPhotos: ObservableObject {
    static let shared = PinPhotos()

    @Published private(set) var images: [String: UIImage] = [:]
    private var requested: Set<String> = []

    func image(for place: Place) -> UIImage? { images[place.id.uuidString] }

    func image(key: String) -> UIImage? { images[key] }

    func load(_ places: [Place]) {
        for place in places { load(place) }
    }

    /// Yerin fotoğrafını (Wikipedia ya da yakında çekilmiş) bir kez arar.
    func load(_ place: Place) {
        load(key: place.id.uuidString) {
            await WikipediaService.shared.photo(name: place.name, city: place.city,
                                                latitude: place.latitude, longitude: place.longitude,
                                                englishTitle: place.wikipediaTitle)
        }
    }

    /// Fotoğrafın adresini `find` ile bir kez bulur, indirip küçültür.
    func load(key: String, find: @escaping () async -> URL?) {
        guard !requested.contains(key) else { return }
        requested.insert(key)
        Task {
            guard let url = await find(),
                  let loaded = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: loaded.0) else { return }
            images[key] = Self.square(image, side: 120)
        }
    }

    /// Ortadan kare kırpılmış küçük resim (pinler küçük; bellek az dolsun).
    private static func square(_ image: UIImage, side: CGFloat) -> UIImage {
        let scale = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }
}

/// Haritadaki kayıtlı yer pini (resme çevrilip haritaya konur): türün
/// renkli dairesi ya da yerin yuvarlak fotoğrafı (köşesinde türün küçük
/// simgesi); "Tüm yerler"de köşesinde gün numarası; istenirse altında adı.
struct PlacePinImage: View {
    let category: PlaceCategory
    var size: CGFloat = 32
    var photo: UIImage?
    var day: Int?
    var title: String?

    /// Pinin çevresindeki boşluk: gölge ve köşe rozetleri kesilmesin.
    static let margin: CGFloat = 8

    /// Pinin kapladığı yükseklik (boşluk dahil); konuma pinin ortası oturur.
    static func blockHeight(size: CGFloat, photo: Bool) -> CGFloat {
        (photo ? size + 10 : size) + margin * 2
    }

    var body: some View {
        VStack(spacing: -4) {
            pin
                .overlay(alignment: .topTrailing) {
                    if let day {
                        DayBadge(number: day + 1, size: 16).offset(x: 7, y: -5)
                    }
                }
                .padding(Self.margin)
            if let title {
                MapTitle(text: title)
            }
        }
    }

    @ViewBuilder
    private var pin: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size + 10, height: size + 10)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .overlay(alignment: .bottomTrailing) {
                    CategoryBadge(category: category, size: 16).offset(x: 3, y: 3)
                }
                .softShadow()
        } else {
            CategoryPin(category: category, size: size)
        }
    }
}

/// Pinin altındaki ad: beyaz kenarlı koyu yazı (Google Maps'teki gibi).
struct MapTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .shadow(color: .white, radius: 0, x: 1, y: 1)
            .shadow(color: .white, radius: 0, x: -1, y: -1)
            .shadow(color: .white, radius: 0, x: 1, y: -1)
            .shadow(color: .white, radius: 0, x: -1, y: 1)
            .padding(.horizontal, 2)
    }
}

extension GoogleMap.Marker {
    /// Kayıtlı yerin pini; dokununca `onTap`.
    @MainActor
    static func place(_ place: Place, size: CGFloat = 32, photo: UIImage? = nil, day: Int? = nil,
                      showsTitle: Bool = false, zIndex: Int32 = 0,
                      onTap: (() -> Void)? = nil) -> GoogleMap.Marker {
        let title = showsTitle ? place.name : nil
        let key = "\(place.name)|\(place.category.rawValue)|\(size)|\(photo.map { "\($0.hash)" } ?? "-")|\(day ?? -1)|\(title ?? "")"
        return GoogleMap.Marker(id: place.id.uuidString, coordinate: place.coordinate, key: key,
                                pinHeight: PlacePinImage.blockHeight(size: size, photo: photo != nil),
                                zIndex: zIndex, onTap: onTap) {
            PlacePinImage(category: place.category, size: size, photo: photo, day: day, title: title)
        }
    }
}

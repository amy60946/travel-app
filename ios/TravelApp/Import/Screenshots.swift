import Photos
import UIKit

/// "Yeri belirle" için ekran görüntüleri. Kullanıcı Fotoğraflar'a tam erişim
/// verdiyse, gönderiyi açtıktan sonra aldığı ekran görüntüsü uygulamaya
/// dönünce kendiliğinden bulunur; vermediyse ekran görüntüsünü kendisi seçer.
enum Screenshots {
    static var canReadAutomatically: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    /// Fotoğraflar izni ister; yalnızca tam erişim yeni ekran görüntülerini gösterir.
    static func requestAccess() async -> Bool {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized
    }

    /// `date`'ten sonra alınan en yeni ekran görüntüsü.
    static func newest(after date: Date) async -> UIImage? {
        guard canReadAutomatically,
              let album = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil).firstObject
        else { return nil }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(in: album, options: options).firstObject else { return nil }
        return await image(for: asset)
    }

    private static func image(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

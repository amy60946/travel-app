import Foundation
import ObjectiveC
import SwiftUI

/// Uygulamanın dili: Türkçe ya da İngilizce, Ayarlar'dan seçilir; varsayılan
/// Türkçe (Oguz, 2026-10-29). Arayüz, Wikipedia/Wikivoyage içerikleri ve
/// sesli anlatım bu dilde. Seçim hemen geçerli olur: uygulamanın yazıları
/// seçilen dilin dosyasından okunur ve ekranlar yeniden çizilir.
enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// Dilin kendi dilindeki adı (çevrilmez).
    var nativeName: String {
        switch self {
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    var locale: Locale { Locale(identifier: self == .turkish ? "tr_TR" : "en_US") }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .turkish
    }

    /// Açılışta bir kez: yazılar seçili dilin dosyasından okunsun; iPhone'un
    /// sistem pencereleri de (izin soruları...) bir sonraki açılışta bu dilde olsun.
    static func activate() {
        object_setClass(Bundle.main, LanguageBundle.self)
        UserDefaults.standard.set([current.rawValue], forKey: "AppleLanguages")
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// Seçili dilin yazı dosyaları (ör. en.lproj).
    fileprivate static var bundle: Bundle? {
        let code = current.rawValue
        if let cached = bundles[code] { return cached }
        let bundle = mainBundlePath(code).flatMap(Bundle.init(path:))
        bundles[code] = bundle
        return bundle
    }

    private static var bundles: [String: Bundle] = [:]

    private static func mainBundlePath(_ code: String) -> String? {
        // Bundle.main'in sınıfı değiştiği için yolu kendi üstünden değil, doğrudan sorarız.
        Bundle(path: Bundle.main.bundlePath)?.path(forResource: code, ofType: "lproj")
    }
}

/// Uygulamanın yazılarını iPhone'un dilinden değil, seçilen dilden okur.
private final class LanguageBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLanguage.bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

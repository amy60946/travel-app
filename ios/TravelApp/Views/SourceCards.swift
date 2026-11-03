import SwiftUI

/// Yer penceresinde Wikidata'dan kısa bilgiler: yapım yılı, mimar, üslup,
/// yükseklik, yıllık ziyaretçi, koruma statüsü ve resmi site.
struct PlaceFactsCard: View {
    let facts: WikidataService.Facts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bilgiler").font(Theme.headline)
            VStack(alignment: .leading, spacing: 8) {
                if let built = facts.built { row("Yapım", built) }
                if !facts.architects.isEmpty { row("Mimar", facts.architects.joined(separator: ", ")) }
                if !facts.styles.isEmpty { row("Mimari üslup", facts.styles.joined(separator: ", ")) }
                if let height = facts.height {
                    row("Yükseklik", "\(height.formatted(.number.precision(.fractionLength(0...1)))) m")
                }
                if let visitors = facts.visitorsPerYear { row("Yılda ziyaretçi", Self.count(visitors)) }
                if !facts.heritage.isEmpty { row("Koruma", facts.heritage.joined(separator: ", ")) }
                if let website = facts.website {
                    Link(destination: website) {
                        row("Resmi site", website.host()?.replacingOccurrences(of: "www.", with: "") ?? website.absoluteString,
                            underline: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, underline: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Theme.font(14))
                .foregroundStyle(Theme.muted)
                .frame(width: 116, alignment: .leading)
            Text(verbatim: value)
                .font(Theme.font(14, .semibold))
                .underline(underline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 3.500.000 → "3,5 milyon"; daha azı rakamla.
    static func count(_ value: Int) -> String {
        guard value >= 1_000_000 else { return value.formatted() }
        let millions = (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(millions) milyon")
    }
}

/// Wikivoyage'da gezginlerin yazdığı not: kısa açıklama, açılış saati, fiyat.
struct TravelerNoteCard: View {
    let listing: WikivoyageListings.Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gezgin notu").font(Theme.headline)
            Text(listing.content).font(Theme.body)
            if let hours = listing.hours {
                Label { Text(verbatim: hours) } icon: { Image(systemName: "clock") }
                    .font(Theme.font(14))
            }
            if let price = listing.price {
                Label { Text(verbatim: price) } icon: { Image(systemName: "creditcard") }
                    .font(Theme.font(14))
            }
            if let url = listing.pageURL {
                // CC BY-SA lisansı gereği kaynak.
                Link(destination: url) {
                    Text(listing.translatedFrom == nil
                         ? LocalizedStringKey("Kaynak: Wikivoyage (CC BY-SA)")
                         : LocalizedStringKey("Kaynak: Wikivoyage (CC BY-SA), Türkçeye çevrildi"))
                        .font(Theme.caption)
                        .underline()
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WikivoyageListings.Listing {
    /// Wikipedia yazısı olmayan yerde "Dinle" bu notu okur.
    var summary: WikipediaService.Summary {
        WikipediaService.Summary(title: name, extract: content, pageURL: pageURL, thumbnailURL: nil,
                                 language: language, translatedFrom: translatedFrom)
    }
}

import MapKit
import SwiftUI

/// Yeni gezi (Polarsteps "Where do you want to go?"): şehir ya da ülke ara;
/// seçilen şehirler üstte hap olarak durur, kayıtlı şehirlerin "+" ile
/// eklenir. Ülkeye dokununca o ülkenin şehirleri açılır. Var olan geziye
/// şehir eklerken de bu ekran açılır ("Sıradaki durağın neresi?").
struct NewTripView: View {
    enum Mode: Equatable {
        case new
        /// Geziye, verilen sıraya şehir ekle.
        case add(journeyID: UUID, index: Int)
    }

    let mode: Mode
    var onCreated: (UUID) -> Void = { _ in }
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = CitySearch()
    @State private var picked: [CityChoice] = []
    @State private var resolving: String?
    @State private var countryPath: [String] = []

    var body: some View {
        NavigationStack(path: $countryPath) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: mode == .new ? "Yeni gezi" : "Şehir ekle") { dismiss() }
                Text(mode == .new ? LocalizedStringKey("Nereye gidiyorsun?") : LocalizedStringKey("Sıradaki durağın neresi?"))
                    .font(Theme.font(26, .bold))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                SearchField(text: $search.query, prompt: "Şehir ya da ülke ara", isSearching: search.isSearching)
                    .padding(.horizontal, 20)
                if !picked.isEmpty { chips }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                            savedCities
                        } else {
                            results
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .overlay(alignment: .bottom) { finishButton }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { code in
                if let country = Country.find(code) {
                    CountryView(country: country, mode: .pick(isPicked: isPicked, toggle: toggle))
                        .overlay(alignment: .bottom) { finishButton }
                }
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .task { openLaunchScreen() }
    }

    // MARK: - Parçalar

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(picked) { city in
                    Button { toggle(city) } label: {
                        HStack(spacing: 6) {
                            if let flag = city.flag { Text(flag) }
                            Text(city.name).font(Theme.font(14, .semibold))
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(city.name), çıkar"))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var results: some View {
        if !search.countries.isEmpty {
            SectionTitle("Ülkeler")
            ForEach(search.countries) { country in
                NavigationLink(value: country.code) {
                    ResultRow(title: country.name, subtitle: Continent.of(country.code)?.name ?? "") {
                        Text(country.flag)
                            .font(.system(size: 30))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.surface)
                    } trailing: {
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        SectionTitle("Şehirler")
        if !search.isSearching && search.cities.isEmpty {
            Text("Sonuç bulunamadı.").font(Theme.font(14)).foregroundStyle(Theme.muted)
        }
        ForEach(search.cities, id: \.self) { completion in
            Button { Task { await pick(completion) } } label: {
                ResultRow(title: completion.title, subtitle: completion.subtitle) {
                    // Pin simgesi yerine şehrin fotoğrafı (Oguz, 2026-10-29).
                    CityPhoto(name: completion.title.components(separatedBy: ",").first ?? completion.title)
                } trailing: {
                    if resolving == completion.title {
                        ProgressView().frame(width: 40, height: 40)
                    } else {
                        Image(systemName: picked.contains(where: { $0.name == completion.title }) ? "checkmark" : "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1.5))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        Text("Arama: Apple Haritalar")
            .font(Theme.font(12))
            .foregroundStyle(Theme.muted)
            .padding(.top, 10)
    }

    /// Kayıtlı yerlerin olduğu şehirler (geziye eklenmiş olanlar hariç).
    @ViewBuilder
    private var savedCities: some View {
        let inJourney: Set<String> = {
            if case .add(let id, _) = mode { return Set(store.journey(id)?.stops.map(\.city) ?? []) }
            return []
        }()
        let cities = store.cities.filter { $0.placeCount > 0 && !inJourney.contains($0.name) }
        if !cities.isEmpty {
            SectionTitle("Kayıtlı şehirlerin")
            ForEach(cities) { city in
                let choice = CityChoice(name: city.name, latitude: city.latitude, longitude: city.longitude)
                ResultRow(title: city.name, subtitle: String(localized: "\(city.placeCount) kayıtlı yer")) {
                    CityPhoto(name: city.name, cover: city.coverPlace)
                } trailing: {
                    AddCircleButton(isAdded: isPicked(choice)) { toggle(choice) }
                }
            }
        }
        Text("Şehir adını yaz ya da bir ülke seç; Keşfet sekmesinde kıtalara ve ülkelere göz atabilirsin.")
            .font(Theme.font(14))
            .foregroundStyle(Theme.muted)
            .padding(.top, 20)
    }

    @ViewBuilder
    private var finishButton: some View {
        if !picked.isEmpty {
            let count = picked.count
            WideButton(title: mode == .new
                       ? String(localized: "Devam · \(count) şehir")
                       : String(localized: "Ekle · \(count) şehir")) { finish() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.white)
        }
    }

    // MARK: - İşlemler

    private func isPicked(_ city: CityChoice) -> Bool {
        let name = store.canonical(city).name
        return picked.contains { $0.name == name }
    }

    private func toggle(_ city: CityChoice) {
        let city = store.canonical(city)
        if let index = picked.firstIndex(where: { $0.name == city.name }) {
            picked.remove(at: index)
        } else {
            picked.append(city)
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        guard resolving == nil else { return }
        resolving = completion.title
        let choice = await CitySearch.resolve(completion)
        resolving = nil
        guard let choice else { return }
        if !isPicked(choice) { toggle(choice) }
        search.query = ""
    }

    private func finish() {
        switch mode {
        case .new:
            let id = store.createJourney(cities: picked)
            dismiss()
            onCreated(id)
        case .add(let journeyID, let index):
            store.addStops(picked, to: journeyID, at: index)
            dismiss()
        }
    }

    /// Yalnızca geliştirme sürümünde: `-screen newTrip` örnek bir arama ve
    /// seçilmiş iki şehirle açılır (ekran görüntüleri için).
    private func openLaunchScreen() {
        #if DEBUG
        let screen = UserDefaults.standard.string(forKey: "screen")
        if screen == "newTrip", picked.isEmpty {
            picked = [CityChoice(name: "Kyoto", countryCode: "JP", latitude: 35.0116, longitude: 135.7681, englishTitle: "Kyoto"),
                      CityChoice(name: "Osaka", countryCode: "JP", latitude: 34.6937, longitude: 135.5023, englishTitle: "Osaka")]
            search.query = "Par"
        }
        #endif
    }
}

// MARK: - Plana ekle

/// "Plana ekle" (Polarsteps "Add to plan"): şehir hangi geziye eklensin;
/// ya da bu şehirle yeni gezi.
struct AddToPlanSheet: View {
    let city: CityChoice
    var onOpenJourney: (UUID) -> Void = { _ in }
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let name = store.canonical(city).name
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Plana ekle") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        CityPhoto(name: city.name, englishTitle: city.englishTitle)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(city.name).font(Theme.font(20, .bold))
                        if let flag = city.flag { Text(flag).font(.system(size: 20)) }
                    }
                    SectionTitle("Gezilerim")
                    Button {
                        let id = store.createJourney(cities: [city])
                        dismiss()
                        onOpenJourney(id)
                    } label: {
                        ResultRow(title: String(localized: "Yeni gezi"), subtitle: String(localized: "\(name) ile başla")) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Theme.surface)
                        } trailing: {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(store.journeys) { journey in
                        let added = journey.stops.contains { $0.city == name }
                        ResultRow(title: journey.name, subtitle: journeySubtitle(journey)) {
                            CityPhoto(name: journey.stops.first?.city ?? "", englishTitle: journey.stops.first?.englishTitle,
                                      cover: store.cities.first { $0.name == journey.stops.first?.city }?.coverPlace)
                        } trailing: {
                            AddCircleButton(isAdded: added) {
                                guard !added else { return }
                                store.addStops([city], to: journey.id)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
        // iOS 26'da yarım pencere cam gibi saydam; arkadaki yazı karışmasın.
        .presentationBackground(.white)
        .presentationCornerRadius(Theme.sheetRadius)
    }

    private func journeySubtitle(_ journey: Journey) -> String {
        let days = store.days(of: journey).reduce(0, +)
        return String(localized: "\(journey.stops.count) şehir · \(days) gün")
    }
}

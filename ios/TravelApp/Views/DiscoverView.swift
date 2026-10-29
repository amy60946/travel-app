import MapKit
import SwiftUI

/// Keşfet (Polarsteps Explore gibi): dünya haritasının üstünde kayan
/// panel; "Keşfet" bölümünde arama, "Senin için" ülke kartları (fotoğraf,
/// "N yer", kaydet) ve kıtalar; "Koleksiyonlar" bölümünde kullanıcının
/// koleksiyonları. Panel ortada açılır, yukarı çekince ekranı kaplar.
/// İçerik Wikipedia ve Wikivoyage'dan (ücretsiz, kaynaklı).
struct DiscoverView: View {
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @StateObject private var search = CitySearch()
    @State private var photos: [String: URL] = [:]
    @State private var countryInfo: [String: DiscoverService.PageInfo] = [:]
    @State private var resolving: String?
    @State private var section = 0
    @State private var panelStop = 1
    @State private var panelHeight: CGFloat = 400
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 25), distance: 24_000_000))
    @FocusState private var searchFocused: Bool

    private var countries: [Country] {
        Country.forYou(visited: store.journeys.flatMap(\.stops).compactMap(\.countryCode))
    }

    /// Koleksiyonlardaki konumu bilinen şeyler (haritada).
    private var collected: [CollectionItem] {
        var seen = Set<String>()
        return store.collections.flatMap(\.items).filter { $0.coordinate != nil && seen.insert($0.key).inserted }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            globe

            Text(section == 0 ? LocalizedStringKey("Keşfet") : LocalizedStringKey("Koleksiyonlar"))
                .font(Theme.font(34, .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            DraggablePanel(stops: [.height(150), .fraction(0.55), .fraction(1)], selection: $panelStop,
                           onSettle: { panelHeight = $0 }) {
                Picker("", selection: $section) {
                    Text("Keşfet").tag(0)
                    Text("Koleksiyonlar").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    if section == 0 {
                        discover
                    } else {
                        CollectionsSection(path: $path)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
        }
        .onChange(of: searchFocused) { _, focused in
            // Yazarken sonuçlar görünsün: panel ekranı kaplar.
            if focused { withAnimation(.snappy) { panelStop = 2 } }
        }
        .task {
            #if DEBUG
            let screen = UserDefaults.standard.string(forKey: "screen")
            if screen == "collections" || screen == "newCollection" { section = 1 }
            if screen == "discoverTall" { panelStop = 2 }
            #endif
            let titles = countries.map(\.title)
            async let continentTask = DiscoverService.shared.info(Continent.all.map(\.photoTitle), from: .wikipedia)
            async let countryTask = DiscoverService.shared.info(titles, from: .wikivoyage)
            photos = await continentTask.compactMapValues(\.photo)
            countryInfo = await countryTask
        }
    }

    // MARK: - Harita

    private var globe: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if section == 0 {
                ForEach(countries) { country in
                    if let info = countryInfo[country.title], let latitude = info.latitude, let longitude = info.longitude {
                        Annotation(country.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                   anchor: .center) {
                            Button { path.append(.country(country.code)) } label: {
                                Text(country.flag)
                                    .font(.system(size: 17))
                                    .frame(width: 30, height: 30)
                                    .background(.white, in: Circle())
                                    .softShadow()
                            }
                            .buttonStyle(.plain)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            } else {
                ForEach(collected) { item in
                    if let coordinate = item.coordinate {
                        Annotation(item.displayName, coordinate: coordinate, anchor: .center) {
                            CollectionItemPhoto(item: item)
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                                .softShadow()
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            UserAnnotation()
        }
        .mapStyle(.imagery(elevation: .realistic))
        .safeAreaPadding(.top, 40)
        .safeAreaPadding(.bottom, panelHeight)
        .ignoresSafeArea()
    }

    // MARK: - Keşfet bölümü

    @ViewBuilder
    private var discover: some View {
        SearchField(text: $search.query, prompt: "Şehir ya da ülke ara", isSearching: search.isSearching,
                    focus: $searchFocused)
            .padding(.top, 4)
        if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
            forYou
            continents
        } else {
            results
        }
    }

    /// "Senin için": iki sütun ülke kartları.
    private var forYou: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Senin için")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(countries) { country in
                    // Kartın içinde kaydet düğmesi var; kartın kendisi düğme değil, dokunulur.
                    CountryCard(country: country, photo: countryInfo[country.title]?.photo)
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(.country(country.code)) }
                        .accessibilityAddTraits(.isButton)
                }
            }
            Text("Fotoğraflar ve yer sayısı: Wikivoyage (CC BY-SA)")
                .font(Theme.font(12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
    }

    private var continents: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Kıtalar")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Continent.all) { continent in
                    Button { path.append(.continent(continent.id)) } label: {
                        PhotoTile(url: photos[continent.photoTitle], title: continent.name,
                                  subtitle: String(localized: "\(continent.countries.count) ülke"))
                            .frame(height: 150)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Fotoğraflar: Wikipedia / Wikimedia Commons")
                .font(Theme.font(12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var results: some View {
        if !search.countries.isEmpty {
            SectionTitle("Ülkeler")
            ForEach(search.countries) { country in
                Button { path.append(.country(country.code)) } label: {
                    ResultRow(title: country.name, subtitle: Continent.of(country.code)?.name ?? "") {
                        CollectionItemPhoto(item: .country(country))
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
            Button { Task { await open(completion) } } label: {
                ResultRow(title: completion.title, subtitle: completion.subtitle) {
                    // Pin simgesi yerine şehrin fotoğrafı (Oguz, 2026-10-29).
                    CityPhoto(name: completion.title.components(separatedBy: ",").first ?? completion.title)
                } trailing: {
                    if resolving == completion.title {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func open(_ completion: MKLocalSearchCompletion) async {
        guard resolving == nil else { return }
        resolving = completion.title
        let choice = await CitySearch.resolve(completion)
        resolving = nil
        if let choice { path.append(.cityGuide(choice)) }
    }
}

/// "Senin için" ülke kartı (Polarsteps gibi): manzara fotoğrafı, solda
/// bayrak, sağ üstte kaydet, altta ad ve kaç yer olduğu (Wikivoyage'daki
/// şehirler ve diğer yerler).
struct CountryCard: View {
    let country: Country
    let photo: URL?
    @State private var placeCount: Int?

    var body: some View {
        RemoteImage(url: photo)
            .overlay {
                if photo == nil { Text(country.flag).font(.system(size: 44)) }
            }
            .frame(height: 190)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(country.name).font(Theme.font(19, .bold)).lineLimit(2)
                    if let placeCount, placeCount > 0 {
                        Text("\(placeCount) yer").font(Theme.font(12, .semibold)).opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(country.flag)
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                CollectButton(item: .country(country), size: 32).padding(8)
            }
            .task(id: country.code) {
                placeCount = await DiscoverService.shared.places(countryTitle: country.title).count
            }
    }
}

// MARK: - Kıta

/// Kıta: haritada ülkeler (bayrakla), altta ülke kartları (Wikivoyage manzarası).
struct ContinentView: View {
    let continent: Continent
    @Binding var path: [Route]
    @Environment(\.dismiss) private var dismiss
    @State private var info: [String: DiscoverService.PageInfo] = [:]
    @State private var position: MapCameraPosition

    init(continent: Continent, path: Binding<[Route]>) {
        self.continent = continent
        _path = path
        _position = State(initialValue: .camera(MapCamera(centerCoordinate: continent.center, distance: continent.distance)))
    }

    private var countries: [Country] { continent.countries.sorted { $0.name < $1.name } }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 300)
                .overlay(alignment: .topLeading) {
                    CircleIconButton(systemImage: "chevron.left") { dismiss() }
                        .accessibilityLabel(Text("Geri"))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(continent.name).font(Theme.title).padding(.top, 16)
                    Text("\(continent.countries.count) ülke")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 14)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(countries) { country in
                            Button { path.append(.country(country.code)) } label: {
                                PhotoTile(url: info[country.title]?.photo, title: "\(country.flag) \(country.name)",
                                          placeholder: country.flag)
                                    .frame(height: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Fotoğraflar: Wikivoyage / Wikimedia Commons (CC BY-SA)")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { info = await DiscoverService.shared.info(continent.countries.map(\.title), from: .wikivoyage) }
    }

    private var map: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(countries) { country in
                if let page = info[country.title], let latitude = page.latitude, let longitude = page.longitude {
                    Annotation(country.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                               anchor: .center) {
                        Button { path.append(.country(country.code)) } label: {
                            Text(country.flag)
                                .font(.system(size: 17))
                                .frame(width: 30, height: 30)
                                .background(.white, in: Circle())
                                .softShadow()
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

// MARK: - Ülke

/// Ülke sayfasında şehrin "+" düğmesi ne yapsın.
enum CityPickMode {
    /// Keşfet: şehre dokununca rehberi açılır, "+" "Plana ekle"yi açar.
    case discover(open: (CityChoice) -> Void)
    /// Yeni gezi: "+" şehri seçime ekler ya da çıkarır.
    case pick(isPicked: (CityChoice) -> Bool, toggle: (CityChoice) -> Void)
}

/// Ülke (Polarsteps Morocco gibi): haritada şehirler, Türkçe Wikipedia
/// özeti ve Wikivoyage'ın önemli şehirler listesi (fotoğraf, ad, tek satır
/// açıklama, "+").
struct CountryView: View {
    let country: Country
    let mode: CityPickMode
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var summary: WikipediaService.Summary?
    @State private var cities: [DiscoverService.GuideCity] = []
    @State private var loading = true
    @State private var wiki: [String: DiscoverService.PageInfo] = [:]
    @State private var voyage: [String: DiscoverService.PageInfo] = [:]
    /// Türkçe açıklamalar. Uygulama Türkçeyken İngilizcesi hiç gösterilmez;
    /// çeviri gelmezse satırda yalnızca ad kalır.
    @State private var descriptions: [String]?
    @State private var position: MapCameraPosition = .automatic
    @State private var expanded = false
    @State private var planTarget: CityChoice?

    private var choices: [CityChoice] { cities.compactMap { choice(for: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 260)
                .overlay(alignment: .topLeading) {
                    CircleIconButton(systemImage: "chevron.left") { dismiss() }
                        .accessibilityLabel(Text("Geri"))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .overlay(alignment: .topTrailing) {
                    CollectButton(item: .country(country), size: 40, opensForScreenshot: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(country.name).font(Theme.title).lineLimit(2)
                            if let continent = Continent.of(country.code) {
                                Text(continent.name).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.top, 16)

                    if let summary {
                        Text(summary.extract)
                            .font(Theme.font(15))
                            .lineLimit(expanded ? nil : 4)
                            .padding(.top, 12)
                        Button(expanded ? LocalizedStringKey("Daha az") : LocalizedStringKey("Devamını oku")) {
                            withAnimation(.snappy) { expanded.toggle() }
                        }
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(Theme.ink)
                        .underline()
                        .padding(.vertical, 6)
                        WikipediaCredit(summary: summary)
                    }

                    SectionTitle("Şehirler ve yerler")
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if cities.isEmpty {
                        Text("Şehir listesi yüklenemedi. İnternet bağlantını kontrol et.")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                        cityRow(city, index: index)
                    }
                    if !cities.isEmpty {
                        Text("Liste: Wikivoyage (CC BY-SA)")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $planTarget) { AddToPlanSheet(city: $0) }
        .overlay(alignment: .bottom) { UndoToast().padding(.bottom, 16) }
        .animation(.snappy, value: store.undoMessage)
        .task { await load() }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(choices) { city in
                Annotation(city.name, coordinate: city.coordinate, anchor: .bottom) {
                    Button { open(city) } label: {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white, Theme.ink)
                            .softShadow()
                    }
                    .buttonStyle(.plain)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaPadding(.top, 40)
    }

    private func cityRow(_ city: DiscoverService.GuideCity, index: Int) -> some View {
        let choice = self.choice(for: city)
        let description = descriptions.map { $0[index] } ?? (DiscoverService.language == "tr" ? "" : city.summary)
        return HStack(spacing: 14) {
            Button {
                if let choice { open(choice) }
            } label: {
                HStack(spacing: 14) {
                    RemoteImage(url: wiki[city.title]?.photo ?? voyage[city.title]?.photo)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(choice?.name ?? city.name).font(Theme.font(17, .semibold)).lineLimit(1)
                        if !description.isEmpty {
                            Text(description)
                                .font(Theme.font(14))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            AddCircleButton(isAdded: choice.map { isAdded($0) } ?? false) {
                if let choice { add(choice) }
            }
            .disabled(choice == nil)
        }
        .padding(.vertical, 8)
    }

    /// Şehrin seçilebilir hali: ad uygulama dilinde (Türkçe Wikipedia'dan),
    /// konum Wikivoyage listesinden ya da sayfalardan. Konum yoksa nil.
    private func choice(for city: DiscoverService.GuideCity) -> CityChoice? {
        guard let latitude = city.latitude ?? voyage[city.title]?.latitude ?? wiki[city.title]?.latitude,
              let longitude = city.longitude ?? voyage[city.title]?.longitude ?? wiki[city.title]?.longitude
        else { return nil }
        let local = wiki[city.title]?.localTitle?
            .replacingOccurrences(of: "\\s*\\([^)]*\\)$", with: "", options: .regularExpression)
        return CityChoice(name: local ?? city.name, countryCode: country.code,
                          latitude: latitude, longitude: longitude, englishTitle: city.title)
    }

    private func isAdded(_ city: CityChoice) -> Bool {
        switch mode {
        case .discover: store.journey(containing: store.canonical(city).name) != nil
        case .pick(let isPicked, _): isPicked(city)
        }
    }

    private func open(_ city: CityChoice) {
        switch mode {
        case .discover(let show): show(city)
        case .pick(_, let toggle): toggle(city)
        }
    }

    private func add(_ city: CityChoice) {
        switch mode {
        case .discover: planTarget = city
        case .pick(_, let toggle): toggle(city)
        }
    }

    private func load() async {
        guard cities.isEmpty else { return }
        let title = country.title
        async let summaryTask = WikipediaService.shared.summary(englishTitle: title)
        async let citiesTask = DiscoverService.shared.places(countryTitle: title)
        summary = await summaryTask
        cities = await citiesTask
        loading = false
        let titles = cities.map(\.title)
        async let wikiTask = DiscoverService.shared.info(titles, from: .wikipedia)
        async let voyageTask = DiscoverService.shared.info(titles, from: .wikivoyage)
        wiki = await wikiTask
        voyage = await voyageTask
        if let region = MKCoordinateRegion(fitting: choices.map(\.coordinate), padding: 1.3) {
            position = .region(region)
        }
        if DiscoverService.language == "tr" {
            descriptions = await DiscoverService.shared.turkishLines(cities.map(\.summary), key: "cities|\(title)")
        }
    }
}

// MARK: - Şehir rehberi

/// Şehir rehberi (Polarsteps Paris rehberi gibi): büyük fotoğraf, Türkçe
/// Wikipedia özeti ve Dinle, Wikivoyage'dan "Bilmen gerekenler" (nasıl bir
/// yer, ne zaman gidilir, nasıl gidilir...) ve popüler yerler. Altta
/// "Plana ekle".
struct CityGuideView: View {
    let city: CityChoice
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var photo: URL?
    @State private var summary: WikipediaService.Summary?
    @State private var sections: [DiscoverService.GuideSection] = []
    @State private var popular: [WikipediaService.PopularPlace] = []
    @State private var showAddToPlan = false
    @State private var expanded = false
    #if DEBUG
    private static var openedLaunchScreen = false
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RemoteImage(url: photo)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    content
                        .padding(.horizontal, 20)
                        .padding(.bottom, 130)
                }
            }
            .ignoresSafeArea(edges: .top)

            HStack {
                CircleIconButton(systemImage: "chevron.left") { dismiss() }
                    .accessibilityLabel(Text("Geri"))
                Spacer()
                CollectButton(item: .city(city), size: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) { planBar }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddToPlan) {
            AddToPlanSheet(city: city) { id in
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    path.append(.journey(id))
                }
            }
        }
        .task { await load() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(city.name).font(Theme.title).lineLimit(2)
                if let flag = city.flag { Text(flag).font(.system(size: 28)) }
            }
            .padding(.top, 18)
            if let code = city.countryCode, let country = Country.find(code) {
                Button { path.append(.country(code)) } label: {
                    HStack(spacing: 4) {
                        Text(country.name)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }

            if let summary {
                Text(summary.extract)
                    .font(Theme.font(15))
                    .lineLimit(expanded ? nil : 5)
                    .padding(.top, 14)
                Button(expanded ? LocalizedStringKey("Daha az") : LocalizedStringKey("Devamını oku")) {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(Theme.font(14, .semibold))
                .foregroundStyle(Theme.ink)
                .underline()
                .padding(.vertical, 6)
                ListenCard(title: city.name, summary: summary)
                    .padding(.top, 6)
                WikipediaCredit(summary: summary)
                    .padding(.top, 6)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            }

            if !sections.isEmpty {
                SectionTitle("Bilmen gerekenler")
                ForEach(sections) { section in
                    GuideRow(section: section, cityTitle: city.wikiTitle)
                }
                Text(DiscoverService.language == "tr"
                     ? LocalizedStringKey("Kaynak: Wikivoyage (CC BY-SA), Türkçeye çevrildi")
                     : LocalizedStringKey("Kaynak: Wikivoyage (CC BY-SA)"))
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 10)
            }

            if !popular.isEmpty {
                SectionTitle("Popüler yerler")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(popular) { place in
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: place.thumbnailURL)
                                    .frame(width: 150, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(place.title)
                                    .font(Theme.font(14, .semibold))
                                    .lineLimit(2)
                                    .frame(width: 150, alignment: .leading)
                            }
                        }
                    }
                }
                Text("Wikipedia'da son 30 günde en çok okunanlar")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
            }
        }
    }

    private var planBar: some View {
        let journey = store.journey(containing: store.canonical(city).name)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name).font(Theme.font(16, .bold)).lineLimit(1)
                Text(journey.map { String(localized: "\($0.name) gezisinde") } ?? String(localized: "Henüz bir gezide değil"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PrimaryButton(title: "Plana ekle", systemImage: "plus") { showAddToPlan = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.white)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .top) { UndoToast().offset(y: -70) }
        .animation(.snappy, value: store.undoMessage)
    }

    private func load() async {
        let title = city.wikiTitle
        async let photoTask = DiscoverService.shared.photo(title)
        async let summaryTask = WikipediaService.shared.summary(englishTitle: title)
        async let sectionsTask = DiscoverService.shared.guide(cityTitle: title)
        photo = await photoTask
        summary = await summaryTask
        sections = await sectionsTask
        popular = (try? await WikipediaService.shared.popularPlaces(latitude: city.latitude, longitude: city.longitude,
                                                                    limit: 10)) ?? []
        #if DEBUG
        // `-screen addToPlan`: "Plana ekle" penceresi açık (ekran görüntüsü için).
        if !Self.openedLaunchScreen, UserDefaults.standard.string(forKey: "screen") == "addToPlan" {
            Self.openedLaunchScreen = true
            showAddToPlan = true
        }
        #endif
    }
}

/// Rehberde bir soru ("Ne zaman gidilmeli?"); dokununca açılır, yazı
/// uygulama Türkçeyse Türkçeye çevrilir.
private struct GuideRow: View {
    let section: DiscoverService.GuideSection
    let cityTitle: String
    @State private var expanded = false
    @State private var translated: String?
    @State private var translating = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !expanded, translated == nil, DiscoverService.language == "tr" { translating = true }
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Theme.surface, in: Circle())
                    Text(question).font(Theme.font(16, .semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded && translating {
                // İngilizcesi görünmesin; çeviri gelince yazı açılır.
                ProgressView()
                    .padding(.leading, 46)
                    .padding(.bottom, 12)
            } else if expanded && failed {
                // Türkçe seçiliyken İngilizcesi gösterilmez.
                HStack(spacing: 10) {
                    Text("Şu an Türkçeye çevrilemedi.")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.muted)
                    Button("Tekrar dene") { retry() }
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.leading, 46)
                .padding(.bottom, 12)
            } else if expanded {
                Text(translated ?? section.text)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .padding(.leading, 46)
                    .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .task(id: expanded) {
            guard expanded, translated == nil, DiscoverService.language == "tr" else { return }
            await translate()
        }
    }

    private func translate() async {
        translating = true
        failed = false
        translated = await DiscoverService.shared.turkish(section.text, key: "guide|\(cityTitle)|\(section.heading)")
        failed = translated == nil
        translating = false
    }

    private func retry() {
        Task { await translate() }
    }

    private var question: LocalizedStringKey {
        switch section.heading {
        case "Understand": "Nasıl bir yer?"
        case "Climate": "Ne zaman gidilmeli?"
        case "Get in": "Nasıl gidilir?"
        case "Get around": "Şehirde nasıl dolaşılır?"
        case "Sleep": "Nerede kalınır?"
        case "Stay safe": "Güvenli mi?"
        case "Respect": "Nelere dikkat etmeli?"
        default: LocalizedStringKey(section.heading)
        }
    }

    private var symbol: String {
        switch section.heading {
        case "Understand": "info.circle"
        case "Climate": "sun.max"
        case "Get in": "airplane"
        case "Get around": "tram"
        case "Sleep": "bed.double"
        case "Stay safe": "shield"
        case "Respect": "hand.raised"
        default: "book"
        }
    }
}

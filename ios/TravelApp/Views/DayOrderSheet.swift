import SwiftUI

/// Günün sırası için öneri penceresi ("1. gün ⌄" → Akıllı sıra / En kısa
/// yol). Önerilen sıra tahmini saatleri ve nedeniyle gösterilir; "Uygula"
/// demeden hiçbir şey değişmez. Akıllı sırada "Başka bir sıra öner" 2-3
/// seçenek arasında gezer.
struct DayOrderSheet: View {
    enum Mode: Hashable { case smart, shortest }

    let stopID: UUID
    let day: Int
    @State var mode: Mode
    /// Üstte kısa bilgi (ör. "Ichiran saat 14:00'e sabitlendi.").
    var message: String?
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var option = 0
    /// Yerler arası gerçek yürüme süreleri (Geoapify); gelene kadar tahmin.
    @State private var walks = DayPlanner.Walks()

    private var places: [Place] {
        let days = store.dayPlan(stop: stopID)
        return days.indices.contains(day) ? days[day] : []
    }

    private var smartOptions: [[DayPlanner.Stop]] {
        DayPlanner.smartOrders(store.dayStops(places, stop: stopID), walks: walks)
    }

    private var shortest: [DayPlanner.Stop] {
        let stops = store.dayStops(places, stop: stopID)
        return RoutePlanner.nearestNeighborOrder(places.map(\.point))
            .compactMap { point in stops.first { $0.id == point.id } }
    }

    var body: some View {
        let options = smartOptions
        let proposal = mode == .smart ? (options.indices.contains(option) ? options[option] : options.first ?? [])
                                      : shortest
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let message {
                        Label(message, systemImage: "clock")
                            .font(Theme.font(14, .semibold))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                    Picker("Sıra", selection: $mode) {
                        Text("Akıllı sıra").tag(Mode.smart)
                        Text("En kısa yol").tag(Mode.shortest)
                    }
                    .pickerStyle(.segmented)
                    Text(mode == .smart
                         ? LocalizedStringKey("Müze ve tapınaklar sabah, yemek öğle ve akşam saatinde, manzara gün batımına doğru, alışveriş ve bar gün sonunda; yürüme de kısa tutulur. Saat verdiğin yerlere o saatte varılır.")
                         : LocalizedStringKey("Yalnızca mesafeye bakar: en az yürünen sıra."))
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                    summary(proposal)
                    VStack(spacing: 0) {
                        let entries = DayPlanner.schedule(proposal, walks: walks)
                        ForEach(Array(proposal.enumerated()), id: \.element.id) { index, stop in
                            if let place = store.place(stop.id), entries.indices.contains(index) {
                                row(place, entry: entries[index])
                                if index < proposal.count - 1 { Divider().padding(.leading, 116) }
                            }
                        }
                    }
                    if mode == .smart && options.count > 1 {
                        Button {
                            withAnimation(.snappy) { option = (option + 1) % options.count }
                        } label: {
                            Label("Başka bir sıra öner", systemImage: "arrow.triangle.2.circlepath")
                                .font(Theme.font(15, .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .safeAreaInset(edge: .bottom) {
                WideButton(title: String(localized: "Uygula")) { apply(proposal) }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.white)
            }
            .navigationTitle(Text("\(day + 1). günün sırası"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .onChange(of: mode) { option = 0 }
            .task {
                walks = WalkingTimes.shared.table(for: places)
                await WalkingTimes.shared.load(places.map(\.coordinate))
                walks = WalkingTimes.shared.table(for: places)
            }
        }
        .presentationDetents([.large])
    }

    /// "6 durak · ~4 km · yaklaşık 5 sa 30 dk" ve (akıllı sırada) "Öneri 1/3".
    private func summary(_ proposal: [DayPlanner.Stop]) -> some View {
        let walk = DayPlanner.legMinutes(proposal, walks: walks).reduce(0, +)
        let kilometers = walk * 80 / 1000
        let total = DayPlanner.totalMinutes(proposal, walks: walks)
        return HStack {
            Text("\(proposal.count) durak · ~\(kilometers.formatted(.number.precision(.fractionLength(1)))) km · yaklaşık \(DayPlanner.durationText(total))")
                .font(Theme.font(14, .semibold))
            Spacer()
            if mode == .smart, smartOptions.count > 1 {
                Text("Öneri \(option + 1)/\(smartOptions.count)")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func row(_ place: Place, entry: DayPlanner.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(verbatim: DayPlanner.clock(entry.arrival))
                    .font(Theme.font(15, .bold))
                    .monospacedDigit()
                if entry.reason == .pinned {
                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 48, alignment: .leading)
            PlaceRowThumbnail(place: place, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(Theme.font(15, .semibold)).lineLimit(2)
                if let reason = entry.reason.flatMap(Self.reasonText) {
                    Text(reason).font(Theme.font(12)).foregroundStyle(Theme.muted)
                } else {
                    Text(verbatim: "\(place.category.title) · \(DayPlanner.durationText(place.visitDuration))")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    static func reasonText(_ reason: DayPlanner.Reason) -> String? {
        switch reason {
        case .pinned: String(localized: "Saatini sen verdin")
        case .morning: String(localized: "Sabah daha sakin")
        case .lunch: String(localized: "Öğle yemeği saati")
        case .dinner: String(localized: "Akşam yemeği saati")
        case .sunset: String(localized: "Gün batımına doğru")
        case .evening: String(localized: "Günün sonunda")
        }
    }

    private func apply(_ proposal: [DayPlanner.Stop]) {
        switch mode {
        case .smart: store.applyOrder(proposal.map(\.id), day: day, stop: stopID, smart: true)
        case .shortest: store.orderByWalking(day: day, stop: stopID)
        }
        dismiss()
    }
}

/// Bir yere saat ver (ör. restoran 14:00): gün o saate göre kurulur.
struct TimePinSheet: View {
    let place: Place
    let stopID: UUID
    /// Saat kaydedildi ya da kaldırıldı.
    var onSave: (Int?) -> Void = { _ in }
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("\(place.name) için saat")
                    .font(Theme.headline)
                    .multilineTextAlignment(.center)
                DatePicker("Saat", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Text("Gün bu saate göre kurulur: öncesindeki ve sonrasındaki yerler buna göre dizilir.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                WideButton(title: String(localized: "Kaydet")) {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    store.setTime(minutes, for: place, stop: stopID)
                    dismiss()
                    onSave(minutes)
                }
                if store.pinnedTime(of: place, stop: stopID) != nil {
                    Button(role: .destructive) {
                        store.setTime(nil, for: place, stop: stopID)
                        dismiss()
                        onSave(nil)
                    } label: {
                        Text("Saati kaldır").font(Theme.font(15, .semibold))
                    }
                }
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            let minutes = store.pinnedTime(of: place, stop: stopID)
                ?? (place.category == .food ? 13 * 60 : place.category == .bar ? 20 * 60 : 12 * 60)
            time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
    }
}

import SwiftUI

/// Yerin kişisel notu (yer penceresinde ve sayfasında): not varsa kartta,
/// yoksa "Not ekle" düğmesi. Dokununca düzenleme penceresi açılır.
struct PlaceNoteCard: View {
    let note: String
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            if note.isEmpty {
                Label("Not ekle", systemImage: "square.and.pencil")
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Notun").font(Theme.headline)
                        Spacer()
                        Text("Düzenle").font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
                    }
                    Text(note)
                        .font(Theme.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(Color(hex: 0xFFF8E6), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(note.isEmpty ? LocalizedStringKey("Bu yer için kendine not yaz")
                                              : LocalizedStringKey("Notu düzenle")))
    }
}

/// Yeri düzenle: ad, tür ve kişisel not (ör. "Sabah erken git, sıra
/// oluyor"). Şehir planında basılı tutunca menüden ya da yer penceresindeki
/// nottan açılır.
struct PlaceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let place: Place
    private let focusesNote: Bool
    @State private var name: String
    @State private var category: PlaceCategory
    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(place: Place, focusesNote: Bool = false) {
        self.place = place
        self.focusesNote = focusesNote
        _name = State(initialValue: place.name)
        _category = State(initialValue: place.category)
        _note = State(initialValue: place.note)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Yerin adı", text: $name)
                    Picker("Tür", selection: $category) {
                        ForEach(PlaceCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section {
                    TextField("Ör. Sabah erken git, sıra oluyor", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                } header: {
                    Text("Notun")
                } footer: {
                    Text("Yalnızca sen görürsün.")
                }
            }
            .navigationTitle("Yeri düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { if focusesNote { noteFocused = true } }
        }
        .presentationDetents([.medium, .large])
        // Arkadaki liste formun içinden görünmesin.
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationCornerRadius(Theme.sheetRadius)
    }

    private func save() {
        guard var updated = store.place(place.id) else { return dismiss() }
        updated.name = trimmedName
        updated.category = category
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(updated)
        dismiss()
    }
}

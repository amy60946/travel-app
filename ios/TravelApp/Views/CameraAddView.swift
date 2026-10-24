import MapKit
import PhotosUI
import SwiftUI

/// Fotoğrafla ekle: tabela ya da bina fotoğrafındaki yazı iPhone'da
/// okunur, telefonun konumuyla yakındaki yer bulunur ve sormadan eklenir;
/// yanlışsa "Değiştir" ile diğer adaylardan biri seçilir.
struct CameraAddView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = LocationTracker()
    @StateObject private var importer = PlaceImporter()

    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var status: LocalizedStringKey?
    @State private var readLines: [String] = []
    @State private var candidates: [SignReader.Candidate] = []
    @State private var addedPlace: Place?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tabelanın ya da girişin fotoğrafını çek. Yazıyı telefonun kendisi okur, konumunla yakındaki yeri bulur.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }

                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            PrimaryButton(title: "Fotoğraf çek", systemImage: "camera") { showCamera = true }
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Galeriden seç", systemImage: "photo")
                                .font(Theme.font(14, .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.hairline))
                        }
                    }

                    if let status {
                        Text(status).font(Theme.font(15, .semibold))
                    }

                    if let addedPlace {
                        resultCard(addedPlace)
                    } else if !readLines.isEmpty {
                        Text("Okunan yazı: \(readLines.prefix(3).joined(separator: " · "))")
                            .font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Fotoğrafla ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { picked in
                    showCamera = false
                    if let picked { Task { await process(picked) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) {
                guard let pickerItem else { return }
                Task {
                    if let data = try? await pickerItem.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        await process(picked)
                    }
                }
            }
            .onAppear { tracker.start() }
            .onDisappear { tracker.stop() }
        }
        .font(Theme.body)
    }

    private func resultCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eklendi · \(place.city)").font(Theme.caption).foregroundStyle(Theme.muted)
                    Text(place.name).font(Theme.headline)
                }
                Spacer()
                EstimatedTag()
            }
            if candidates.count > 1 {
                Text("Yanlış yer mi? Değiştir:").font(Theme.caption).foregroundStyle(Theme.muted)
                ForEach(candidates.filter { $0.item.name != place.name }) { candidate in
                    Button {
                        replace(place, with: candidate)
                    } label: {
                        HStack {
                            Text(candidate.item.name ?? "")
                            Spacer()
                            Text("\(Int(candidate.distance)) m").foregroundStyle(Theme.muted)
                        }
                        .font(Theme.font(14))
                    }
                    .buttonStyle(.plain)
                }
            }
            SecondaryButton(title: "Geri al", systemImage: "arrow.uturn.backward") {
                store.undo()
                addedPlace = nil
                status = nil
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func process(_ picked: UIImage) async {
        image = picked
        addedPlace = nil
        candidates = []
        status = "Yazı okunuyor…"
        readLines = await SignReader.readText(from: picked)
        guard !readLines.isEmpty else {
            status = "Fotoğrafta okunabilir yazı bulunamadı. Tabelaya daha yakından dene."
            return
        }
        guard let location = tracker.location else {
            status = "Konumun alınamadı. Konum iznini kontrol et ve tekrar dene."
            return
        }
        status = "Yakındaki yerler aranıyor…"
        candidates = await SignReader.candidates(for: readLines, near: location)
        guard let best = candidates.first else {
            status = "Yakında bu yazıyla eşleşen yer bulunamadı."
            return
        }
        let place = await makePlace(from: best)
        store.add(place, plan: false)
        addedPlace = place
        status = nil
    }

    private func makePlace(from candidate: SignReader.Candidate, keeping id: UUID? = nil) async -> Place {
        let c = candidate.item.placemark.coordinate
        let city = await importer.city(for: CLLocation(latitude: c.latitude, longitude: c.longitude),
                                       knownCities: store.cities)
        var place = Place(name: candidate.item.name ?? String(localized: "Yer"), city: city,
                          latitude: c.latitude, longitude: c.longitude,
                          category: PlaceCategory(candidate.item.pointOfInterestCategory),
                          source: .photo, isEstimated: true)
        if let id { place.id = id }
        return place
    }

    private func replace(_ place: Place, with candidate: SignReader.Candidate) {
        Task {
            let updated = await makePlace(from: candidate, keeping: place.id)
            store.update(updated)
            addedPlace = updated
        }
    }
}

/// iPhone kamerası.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

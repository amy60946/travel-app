import AuthenticationServices
import SwiftUI

/// "Apple ile giriş" düğmesi (siyah). Girince paylaşılan gezilerin listesi
/// sunucudan alınır; hata olursa kısa bir uyarı çıkar.
struct AppleSignInButton: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = Account.shared
    @State private var error: String?
    @State private var working = false

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            account.prepare(request)
        } onCompletion: { result in
            Task {
                working = true
                defer { working = false }
                do {
                    try await account.complete(result)
                    await TripSharing.shared.refreshMine(store: store)
                } catch {
                    self.error = (error as? LocalizedError)?.errorDescription
                        ?? String(localized: "Apple ile giriş yapılamadı. Yeniden dene.")
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(Capsule())
        .overlay { if working { ProgressView().tint(.white) } }
        .disabled(working)
        .alert("Giriş yapılamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}

/// Giriş düğmeleri: Apple, Supabase'te açıksa altında Google.
struct SignInButtons: View {
    @ObservedObject private var account = Account.shared

    var body: some View {
        VStack(spacing: 10) {
            AppleSignInButton()
            if account.googleEnabled { GoogleSignInButton() }
        }
        .task { await account.loadProviders() }
    }
}

/// "Google ile giriş yap" (beyaz, Google'ın renkli G'si). Supabase'in giriş
/// sayfası uygulamanın içinde tarayıcı penceresinde açılır; uygulamada
/// Google anahtarı yok.
struct GoogleSignInButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @ObservedObject private var account = Account.shared
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Button { Task { await signIn() } } label: {
            HStack(spacing: 10) {
                Image("GoogleLogo").resizable().frame(width: 18, height: 18)
                Text("Google ile giriş yap").font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .overlay { if working { ProgressView() } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(working)
        .alert("Giriş yapılamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func signIn() async {
        #if DEBUG
        if Account.demoScreen != nil { return }
        #endif
        working = true
        defer { working = false }
        do {
            let url = try account.googleSignInURL()
            let callback = try await webAuthenticationSession.authenticate(using: url,
                                                                           callbackURLScheme: Account.callbackScheme)
            try await account.completeGoogle(callback)
            await TripSharing.shared.refreshMine(store: store)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Vazgeçildi.
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Google ile giriş yapılamadı. Yeniden dene.")
        }
    }
}

/// Profil sekmesinin üstü: girişsizken "Gezilerini paylaş" kartı, girince
/// simge, ad ve "Düzenle".
struct AccountCard: View {
    @ObservedObject private var account = Account.shared
    @State private var editing = false
    @State private var loadFailed = false

    var body: some View {
        if Supabase.isConfigured {
            if let profile = account.profile, account.isSignedIn {
                HStack(spacing: 14) {
                    ProfileAvatar(emoji: profile.emoji, size: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: profile.name.isEmpty ? String(localized: "Gezgin") : profile.name)
                            .font(Theme.font(22, .bold))
                            .lineLimit(1)
                        Text(account.session?.provider == "google"
                             ? LocalizedStringKey("Google ile giriş yapıldı")
                             : LocalizedStringKey("Apple ile giriş yapıldı"))
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Button { editing = true } label: {
                        Text("Düzenle")
                            .font(Theme.font(14, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $editing) { ProfileEditor() }
                .task { if editing == false { try? await account.loadProfile() } }
            } else if account.isSignedIn {
                // Profil yükleniyor (internet yoksa "Yeniden dene").
                HStack(spacing: 14) {
                    ProfileAvatar(emoji: "🧭", size: 60)
                    if loadFailed {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Profil yüklenemedi").font(Theme.font(16, .semibold))
                            Button("Tekrar dene") { Task { await load() } }
                                .font(Theme.font(14, .semibold))
                                .foregroundStyle(Theme.ink)
                                .underline()
                        }
                    } else {
                        ProgressView()
                    }
                    Spacer()
                }
                .task { await load() }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Gezilerini paylaş").font(Theme.font(20, .bold))
                    Text("Giriş yap; gezilerini herkese açık paylaş, başka gezginlerin rotalarını Keşfet'te bul.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    SignInButtons().padding(.top, 4)
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
    }

    private func load() async {
        loadFailed = false
        do {
            try await account.loadProfile()
        } catch {
            loadFailed = true
        }
    }
}

/// Profil simgesi: açık zeminli daire içinde emoji.
struct ProfileAvatar: View {
    let emoji: String
    var size: CGFloat = 40

    var body: some View {
        Text(verbatim: emoji.isEmpty ? "🧭" : emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(Theme.surface, in: Circle())
            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
    }
}

/// Profil sekmesinde girişliyken: gezilerin (herkese açık anahtarıyla),
/// çıkış ve hesabı silme.
struct SharingSection: View {
    @Binding var path: [Route]
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = Account.shared
    @ObservedObject private var sharing = TripSharing.shared
    @State private var busy: UUID?
    @State private var error: String?

    var body: some View {
        if Supabase.isConfigured && account.isSignedIn {
            VStack(alignment: .leading, spacing: 0) {
                title("Paylaşılan geziler")
                if store.journeys.isEmpty {
                    Text("Henüz gezin yok. Bir gezi oluşturunca buradan herkese açık paylaşabilirsin.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.journeys) { journey in
                            journeyRow(journey)
                            if journey.id != store.journeys.last?.id { Divider().padding(.leading, 82) }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    Text("Açık olan geziler Keşfet'te ve aramada görünür; gezide değişiklik yapınca paylaşılan hali de güncellenir. Kişisel notların, uçuş ve konaklama bilgilerin paylaşılmaz.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                }
            }
            .alert("İşlem yapılamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func journeyRow(_ journey: Journey) -> some View {
        let days = store.days(of: journey).reduce(0, +)
        return HStack(spacing: 14) {
            CityPhoto(name: journey.stops.first?.city ?? journey.name, englishTitle: journey.stops.first?.englishTitle)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: journey.name).font(Theme.font(16, .semibold)).lineLimit(1)
                Text(journey.stops.count == 1
                     ? String(localized: "\(days) gün")
                     : String(localized: "\(journey.stops.count) şehir · \(days) gün"))
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if busy == journey.id {
                ProgressView()
            } else {
                Toggle(isOn: Binding(get: { sharing.isShared(journey.id) },
                                     set: { on in Task { await setShared(journey, on) } })) {
                    Text("Herkese açık")
                }
                .labelsHidden()
                .tint(Theme.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func setShared(_ journey: Journey, _ on: Bool) async {
        busy = journey.id
        defer { busy = nil }
        #if DEBUG
        if Account.demoScreen != nil { return }
        #endif
        do {
            if on {
                try await TripSharing.shared.share(journey, store: store)
            } else {
                try await TripSharing.shared.unshare(journey.id)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip yeniden dene.")
        }
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.leading, 4)
            .padding(.top, 28)
            .padding(.bottom, 6)
    }
}

/// Profil sekmesinin sonunda girişliyken: çıkış ve hesabı silme.
struct AccountActionsSection: View {
    @ObservedObject private var account = Account.shared
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        if Supabase.isConfigured && account.isSignedIn {
            VStack(alignment: .leading, spacing: 0) {
                Text("Hesap")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 4)
                    .padding(.top, 28)
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    Button { Task { await account.signOut() } } label: {
                        actionLabel("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                    Button { confirmDelete = true } label: {
                        actionLabel("Hesabı sil", systemImage: "trash", tint: .red)
                    }
                    .buttonStyle(.plain)
                    .disabled(deleting)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .confirmationDialog("Hesabın silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Hesabı sil", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("Profilin ve paylaştığın geziler sunucudan silinir. Telefondaki gezilerin ve kayıtların yerinde kalır.")
            }
            .alert("İşlem yapılamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        #if DEBUG
        if Account.demoScreen != nil { return }
        #endif
        do {
            try await account.deleteAccount()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip yeniden dene.")
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String, tint: Color = Theme.ink) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 22)
            Text(title).font(Theme.font(16, .semibold))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

/// Profili düzenle: ad ve simge.
struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared
    @State private var name = ""
    @State private var emoji = "🧭"
    @State private var saving = false
    @State private var error: String?

    private static let emojis = ["🧭", "🌍", "✈️", "🎒", "🗺️", "🏔️", "🏝️", "🚆", "🚲", "📸", "🍜", "🍝",
                                 "☕️", "🌸", "🌊", "⛩️", "🏛️", "🕌", "🌋", "🏕️", "🚐", "🛶", "🦊", "🐢"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Profili düzenle") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProfileAvatar(emoji: emoji, size: 84)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ad").font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                        TextField("Adın", text: $name)
                            .font(Theme.font(17))
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        Text("Paylaştığın gezilerde bu ad görünür.")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Simge").font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(Self.emojis, id: \.self) { option in
                                Button { emoji = option } label: {
                                    Text(verbatim: option)
                                        .font(.system(size: 26))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(option == emoji ? Theme.ink.opacity(0.12) : Theme.surface,
                                                    in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .stroke(option == emoji ? Theme.ink : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            PrimaryButton(title: "Kaydet") { Task { await save() } }
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(saving ? 0.6 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .onAppear {
            name = account.profile?.name ?? ""
            emoji = account.profile?.emoji ?? "🧭"
        }
        .alert("Kaydedilemedi", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        #if DEBUG
        if Account.demoScreen != nil { dismiss(); return }
        #endif
        do {
            try await account.saveProfile(name: name, emoji: emoji)
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip yeniden dene.")
        }
    }
}

/// Gezinin "…" menüsündeki "Paylaş": giriş, herkese açık anahtarı ve ne
/// paylaşıldığı.
struct ShareTripSheet: View {
    let journeyID: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = Account.shared
    @ObservedObject private var sharing = TripSharing.shared
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Paylaş") { dismiss() }
            VStack(alignment: .leading, spacing: 14) {
                if !Supabase.isConfigured {
                    Text("Paylaşım bu sürümde kapalı.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                } else if !account.isSignedIn {
                    Text("Gezini herkese açık paylaşmak için giriş yap.")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    SignInButtons()
                } else if let journey = store.journey(journeyID) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Herkese açık").font(Theme.font(17, .semibold))
                            Text(sharing.isShared(journeyID)
                                 ? LocalizedStringKey("Keşfet'te ve aramada görünüyor")
                                 : LocalizedStringKey("Yalnızca bu telefonda"))
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if busy {
                            ProgressView()
                        } else {
                            Toggle(isOn: Binding(get: { sharing.isShared(journeyID) },
                                                 set: { on in Task { await setShared(journey, on) } })) {
                                Text("Herkese açık")
                            }
                            .labelsHidden()
                            .tint(Theme.ink)
                        }
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    Label {
                        Text("Şehirler, günler ve yerler paylaşılır; gezide değişiklik yapınca paylaşılan hali de güncellenir. Kişisel notların, uçuş ve konaklama bilgilerin paylaşılmaz. Başkaları gezini kendi gezilerine kopyalayabilir.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .font(Theme.body)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium])
        .alert("İşlem yapılamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func setShared(_ journey: Journey, _ on: Bool) async {
        busy = true
        defer { busy = false }
        #if DEBUG
        if Account.demoScreen != nil { return }
        #endif
        do {
            if on {
                try await TripSharing.shared.share(journey, store: store)
            } else {
                try await TripSharing.shared.unshare(journey.id)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip yeniden dene.")
        }
    }
}

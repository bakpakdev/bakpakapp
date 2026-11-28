import SwiftUI
import PhotosUI
import Supabase
import UIKit

// MARK: - Options

private struct SizeOption: Identifiable, Hashable {
    let id: String
    let label: String
}

private struct StyleOption: Identifiable, Hashable {
    let id: String
    let label: String
}

private let sizeOptions: [SizeOption] = [
    SizeOption(id: "xs", label: "XS"),
    SizeOption(id: "s", label: "S"),
    SizeOption(id: "m", label: "M"),
    SizeOption(id: "l", label: "L"),
    SizeOption(id: "xl", label: "XL"),
]

private let styleOptions: [StyleOption] = [
    StyleOption(id: "streetwear", label: "Streetwear"),
    StyleOption(id: "vintage", label: "Vintage"),
    StyleOption(id: "y2k", label: "Y2K"),
    StyleOption(id: "cottagecore", label: "Cottagecore"),
    StyleOption(id: "minimalist", label: "Minimalist"),
    StyleOption(id: "grunge", label: "Grunge"),
    StyleOption(id: "academia", label: "Academia"),
    StyleOption(id: "sporty", label: "Sporty"),
    StyleOption(id: "preppy", label: "Preppy"),
    StyleOption(id: "skater", label: "Skater"),
    StyleOption(id: "workwear", label: "Workwear"),
    StyleOption(id: "gorpcore", label: "Gorpcore"),
    StyleOption(id: "indie", label: "Indie"),
    StyleOption(id: "retro", label: "Retro"),
    StyleOption(id: "techwear", label: "Techwear"),
    StyleOption(id: "coquette", label: "Coquette"),
    StyleOption(id: "western", label: "Western"),
    StyleOption(id: "formal", label: "Formal"),
    StyleOption(id: "boho", label: "Boho"),
    StyleOption(id: "punk", label: "Punk"),
]

enum EditProfilePrefs {
    static var sizes: String { AccountScopedDefaults.key("popup.editProfile.sizes") }
    static var styles: String { AccountScopedDefaults.key("popup.editProfile.styles") }
    static var tradesOpen: String { AccountScopedDefaults.key("popup.editProfile.tradesOpen") }
    static var showBadge: String { AccountScopedDefaults.key("popup.editProfile.showBadge") }
    static var allowDMs: String { AccountScopedDefaults.key("popup.editProfile.allowDMs") }
    static var gradYear: String { AccountScopedDefaults.key("popup.editProfile.gradYear") }
}

// MARK: - Sub-components

struct EditProfileIOSSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button {
            withAnimation(Motion.snappy) { isOn.toggle() }
            Motion.haptic(.light)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? campusTheme.primary : campusTheme.elevatedSurface)
                    .frame(width: 48, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(campusTheme.primary.opacity(isOn ? 0 : 0.16), lineWidth: 1)
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct EditProfileSectionHeader: View {
    let title: String
    var subtitle: String?
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.lowercased())
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }
}

struct EditProfileCard<Content: View>: View {
    @Environment(\.campusTheme) private var campusTheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }
}

struct EditProfileRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    @Environment(\.campusTheme) private var campusTheme
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .font(Theme.syne(15, weight: .medium))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer(minLength: 8)
                content
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if showDivider {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 18)
            }
        }
    }
}

private struct EditProfileFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct EditProfileFieldStyle: ViewModifier {
    @Environment(\.campusTheme) private var campusTheme

    func body(content: Content) -> some View {
        content
            .font(Theme.syne(15))
            .foregroundStyle(campusTheme.textMuted)
            .tint(campusTheme.primary)
            .multilineTextAlignment(.trailing)
    }
}

/// Small uppercase label above each glass section.
private struct GlassSectionLabel: View {
    let title: String
    var detail: String?
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(Theme.syne(11.5, weight: .bold))
                .tracking(1.3)
            if let detail {
                Text("· \(detail)")
                    .font(Theme.syne(11.5, weight: .medium))
            }
        }
        .foregroundStyle(campusTheme.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.top, 24)
        .padding(.bottom, 9)
    }
}

/// Pill chip: solid when picked, see-through glass when not.
private struct GlassChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(selected ? campusTheme.background : campusTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    Capsule().fill(selected ? campusTheme.textPrimary : campusTheme.textPrimary.opacity(0.07))
                )
                .overlay(
                    Capsule().stroke(campusTheme.textPrimary.opacity(selected ? 0 : 0.16), lineWidth: 1)
                )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }
}

// MARK: - Edit profile

struct EditProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var name = ""
    @State private var username = ""
    @State private var usernameStatus = SupabaseProfileService.UsernameChangeStatus.unlocked
    @State private var showChangeUsername = false
    @State private var changedToast: String?
    @FocusState private var focusedField: BasicInfoField?

    private enum BasicInfoField { case name }
    @State private var bio = ""
    @State private var selectedSizes: Set<String> = []
    @State private var selectedStyles: Set<String> = []
    @State private var isTradesOpen = true
    @State private var showBadge = true
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedPhoto: UIImage?
    @State private var isUploadingPhoto = false

    private let bioLimit = 150

    private var avatarURL: String { authVM.user?.avatar ?? "" }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Text("edit profile")
                        .font(Theme.syne(34, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .padding(.bottom, 18)

                    if let changedToast {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(campusTheme.background)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(campusTheme.textPrimary))
                            Text(changedToast)
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .usernameGlass(20)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    photoSection

                    GlassSectionLabel(title: "basic info")
                    VStack(spacing: 0) {
                        // Tapping anywhere on the row edits the name, not just the text on the right.
                        HStack(spacing: 12) {
                            Text("Name")
                                .font(Theme.syne(15, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer(minLength: 8)
                            TextField("Your name", text: $name)
                                .modifier(EditProfileFieldStyle())
                                .frame(maxWidth: 190)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                        .onTapGesture { focusedField = .name }

                        glassDivider

                        usernameRow
                    }
                    .usernameGlass(24)

                    Text(usernameNote)
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.top, 8)

                    GlassSectionLabel(title: "bio")
                    VStack(alignment: .trailing, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            if bio.isEmpty {
                                Text("Tell campus what you thrift…")
                                    .font(Theme.syne(15))
                                    .foregroundStyle(campusTheme.textMuted.opacity(0.8))
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $bio)
                                .font(Theme.syne(15))
                                .foregroundStyle(campusTheme.textPrimary)
                                .tint(campusTheme.textPrimary)
                                .frame(minHeight: 90)
                                .scrollContentBackground(.hidden)
                                .onChange(of: bio) { newValue in
                                    if newValue.count > bioLimit {
                                        bio = String(newValue.prefix(bioLimit))
                                    }
                                }
                        }
                        Text("\(bio.count)/\(bioLimit)")
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(bio.count >= bioLimit ? Color(hex: "#FF6B6B") : campusTheme.textMuted)
                    }
                    .padding(14)
                    .usernameGlass(24)

                    GlassSectionLabel(title: "thrift filters", detail: "shown on your profile")
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sizes")
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                            EditProfileFlowLayout(spacing: 7) {
                                ForEach(sizeOptions) { size in
                                    GlassChip(label: size.label, selected: selectedSizes.contains(size.id)) {
                                        toggleSize(size.id)
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Styles")
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                            EditProfileFlowLayout(spacing: 7) {
                                ForEach(styleOptions) { style in
                                    GlassChip(label: style.label, selected: selectedStyles.contains(style.id)) {
                                        toggleStyle(style.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .usernameGlass(24)

                    Color.clear.frame(height: 48)
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(campusTheme.textPrimary)
                    } else {
                        Text("save")
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(campusTheme.background)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(Capsule().fill(campusTheme.textPrimary))
                    }
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                .disabled(isSaving)
            }
        }
        .campusPageStyle()
        .navigationDestination(isPresented: $showChangeUsername) {
            ChangeUsernameView(
                currentUsername: username,
                status: usernameStatus
            ) { newName, status in
                username = newName
                usernameStatus = status
                if let u = authVM.user {
                    authVM.user = User(
                        id: u.id, email: u.email, username: newName,
                        firstName: u.firstName, lastName: u.lastName, avatar: u.avatar,
                        bio: u.bio, shopName: u.shopName, dateOfBirth: u.dateOfBirth,
                        country: u.country, isVerified: u.isVerified
                    )
                }
                withAnimation(Motion.snappy) { changedToast = "you're now @\(newName)" }
            }
            .environment(\.campusTheme, campusTheme)
        }
        .task { await loadUsernameStatus() }
        .onChange(of: photoItem) { item in
            Task { await loadAndUploadPhoto(item) }
        }
        .alert("Could not save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear {
            loadFromUser()
            loadLocalPreferences()
        }
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(campusTheme.textPrimary.opacity(0.09))
            .frame(height: 1)
            .padding(.leading, 16)
    }

    /// The username isn't a text box any more: it opens its own screen, and shows a
    /// lock with the unlock date for 14 days after a change.
    private var usernameRow: some View {
        Button {
            focusedField = nil
            Motion.haptic(.light)
            showChangeUsername = true
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("Username")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Spacer(minLength: 8)
                    Text("@\(username)")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(usernameStatus.locked ? campusTheme.textMuted : campusTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: usernameStatus.locked ? "lock.fill" : "chevron.right")
                        .font(.system(size: usernameStatus.locked ? 12 : 13, weight: .bold))
                        .foregroundStyle(campusTheme.textMuted)
                }
                if usernameStatus.locked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(campusTheme.textPrimary.opacity(0.12))
                            Capsule().fill(campusTheme.textPrimary)
                                .frame(width: max(6, geo.size.width * usernameStatus.lockProgress))
                        }
                    }
                    .frame(height: 5)
                    if let until = usernameStatus.unlocksAt {
                        Text("locked · you can change it again \(UsernameDates.long(until))")
                            .font(Theme.syne(11.5, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(usernameStatus.locked ? "Locked. Shows when you can change it again." : "Opens a screen to change your username.")
    }

    private var usernameNote: String {
        "Your @ is how people find you, tag you and leave you reviews. You can change it once every \(SupabaseProfileService.usernameLockDays) days."
    }

    private func loadUsernameStatus() async {
        guard authVM.usesSupabase,
              let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        let status = await SupabaseProfileService.usernameChangeStatus(client: client)
        usernameStatus = status
    }

    private var photoSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let pickedPhoto {
                        Image(uiImage: pickedPhoto)
                            .resizable()
                            .scaledToFill()
                    } else {
                        AvatarView(
                            urlString: avatarURL,
                            size: 96,
                            cornerRadius: 48,
                            initials: name.isEmpty ? "U" : name
                        )
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(campusTheme.isDark ? 0.25 : 0.7), lineWidth: 3))

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: isUploadingPhoto ? "hourglass" : "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(campusTheme.background)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(campusTheme.textPrimary))
                        .overlay(Circle().stroke(campusTheme.background.opacity(0.6), lineWidth: 2))
                }
                .disabled(isUploadingPhoto)
                .offset(x: 2, y: 2)
            }

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Text(isUploadingPhoto ? "uploading…" : "change photo")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .usernameGlass(17)
            }
            .disabled(isUploadingPhoto)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func toggleSize(_ id: String) {
        Motion.haptic(.light)
        if selectedSizes.contains(id) { selectedSizes.remove(id) }
        else { selectedSizes.insert(id) }
    }

    private func toggleStyle(_ id: String) {
        Motion.haptic(.light)
        if selectedStyles.contains(id) { selectedStyles.remove(id) }
        else { selectedStyles.insert(id) }
    }

    private func loadFromUser() {
        guard let u = authVM.user else { return }
        username = u.username
        if let f = u.firstName?.trimmingCharacters(in: .whitespacesAndNewlines),
           let l = u.lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty {
            name = "\(f) \(l)"
        } else if let f = u.firstName, !f.isEmpty {
            name = f
        } else if let s = u.shopName, !s.isEmpty {
            name = s
        }
        bio = u.bio ?? ""
    }

    private func loadLocalPreferences() {
        let d = UserDefaults.standard
        if let sizes = d.array(forKey: EditProfilePrefs.sizes) as? [String] {
            selectedSizes = Set(sizes)
        }
        if let styles = d.array(forKey: EditProfilePrefs.styles) as? [String] {
            selectedStyles = Set(styles)
        }
        if d.object(forKey: EditProfilePrefs.tradesOpen) != nil {
            isTradesOpen = d.bool(forKey: EditProfilePrefs.tradesOpen)
        }
        if d.object(forKey: EditProfilePrefs.showBadge) != nil {
            showBadge = d.bool(forKey: EditProfilePrefs.showBadge)
        }
    }

    private func saveLocalPreferences() {
        let d = UserDefaults.standard
        d.set(Array(selectedSizes), forKey: EditProfilePrefs.sizes)
        d.set(Array(selectedStyles), forKey: EditProfilePrefs.styles)
        d.set(isTradesOpen, forKey: EditProfilePrefs.tradesOpen)
        d.set(showBadge, forKey: EditProfilePrefs.showBadge)
    }

    private func parsedName() -> (first: String, last: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let first = parts.first.map(String.init) ?? ""
        let last = parts.count > 1 ? String(parts[1]) : ""
        return (first, last)
    }

    private func normalizedUsername() -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.82) else {
            saveErrorMessage = "Couldn’t read that photo. Try another."
            showSaveError = true
            return
        }
        pickedPhoto = image
        guard let client = await SupabaseManager.shared.clientWithValidSession() else {
            saveErrorMessage = "Sign in to change your photo."
            showSaveError = true
            return
        }
        do {
            let uid = try await client.auth.session.user.id.uuidString.lowercased()
            let path = "\(uid)/avatar-\(UUID().uuidString.lowercased()).jpg"
            let opts = FileOptions(contentType: "image/jpeg", upsert: true)
            try await client.storage.from("product-images").upload(path, data: jpeg, options: opts)
            let url = try client.storage.from("product-images").getPublicURL(path: path)
            let updated = try await SupabaseProfileService.updateProfile(
                client: client,
                patch: .init(avatar_url: url.absoluteString)
            )
            authVM.user = updated
            Motion.haptic(.medium)
        } catch {
            saveErrorMessage = "Couldn’t upload that photo. Check your connection and try again."
            showSaveError = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        saveLocalPreferences()

        let (firstName, lastName) = parsedName()
        let userName = normalizedUsername()
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)

        if authVM.usesSupabase {
            guard let client = await SupabaseManager.shared.clientWithValidSession() else {
                saveErrorMessage = "You need to be signed in to save your profile."
                showSaveError = true
                return
            }
            do {
                let updated = try await SupabaseProfileService.updateProfile(
                    client: client,
                    patch: .init(
                        // The username only changes on its own screen (ChangeUsernameView).
                        username: nil,
                        first_name: firstName.isEmpty ? nil : firstName,
                        last_name: lastName.isEmpty ? nil : lastName,
                        bio: trimmedBio.isEmpty ? nil : trimmedBio,
                        shop_name: nil,
                        avatar_url: nil,
                        country: nil
                    )
                )
                authVM.user = updated
                dismiss()
            } catch {
                saveErrorMessage = SupabaseProfileService.friendlySaveError(error)
                showSaveError = true
            }
            return
        }

        guard let userId = authVM.user?.id else { return }
        let payload: [String: Any] = [
            "username": userName,
            "firstName": firstName,
            "lastName": lastName,
            "bio": trimmedBio,
        ]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let _: User = try await APIClient.shared.request(path: "/users/\(userId)", method: "PUT", body: body)
            await authVM.refreshMe()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

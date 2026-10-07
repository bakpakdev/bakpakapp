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
]

enum EditProfilePrefs {
    static var sizes: String { AccountScopedDefaults.key("popup.editProfile.sizes") }
    static var styles: String { AccountScopedDefaults.key("popup.editProfile.styles") }
    static var tags: String { AccountScopedDefaults.key("popup.editProfile.tags") }
    static var tradesOpen: String { AccountScopedDefaults.key("popup.editProfile.tradesOpen") }
    static var showBadge: String { AccountScopedDefaults.key("popup.editProfile.showBadge") }
    static var allowDMs: String { AccountScopedDefaults.key("popup.editProfile.allowDMs") }
    static var instagram: String { AccountScopedDefaults.key("popup.editProfile.instagram") }
    static var depop: String { AccountScopedDefaults.key("popup.editProfile.depop") }
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

private struct EditProfileChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(selected ? campusTheme.primary : campusTheme.elevatedSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
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

// MARK: - Edit profile

struct EditProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var selectedSizes: Set<String> = []
    @State private var selectedStyles: Set<String> = []
    @State private var selectedTags: [String] = []
    @State private var isTradesOpen = true
    @State private var showBadge = true
    @State private var instagram = ""
    @State private var instagramConnected = false
    @State private var depop = ""
    @State private var showInstagramAuthSheet = false
    @State private var pendingInstagramHandle = ""
    @State private var isConnectingInstagram = false
    @State private var showDepopSheet = false
    @State private var pendingDepopHandle = ""
    @State private var socialError: String?
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedPhoto: UIImage?
    @State private var isUploadingPhoto = false

    private let bioLimit = 150
    private let maxTags = 10

    private var avatarURL: String { authVM.user?.avatar ?? "" }

    private var suggestedTags: [String] {
        campusTheme.tags
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("edit profile")
                            .font(Theme.syne(36, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text("how campus sees you")
                            .font(Theme.syne(28, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                    photoSection

                    EditProfileSectionHeader(title: "Basic Info")
                    EditProfileCard {
                        EditProfileRow(label: "Name") {
                            TextField("Your name", text: $name)
                                .modifier(EditProfileFieldStyle())
                                .frame(maxWidth: 180)
                        }
                        EditProfileRow(label: "Username", showDivider: false) {
                            TextField("username", text: $username)
                                .modifier(EditProfileFieldStyle())
                                .frame(maxWidth: 180)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }

                    EditProfileSectionHeader(title: "Bio")
                    EditProfileCard {
                        VStack(alignment: .trailing, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                if bio.isEmpty {
                                    Text("Tell campus what you thrift…")
                                        .font(Theme.syne(15))
                                        .foregroundStyle(campusTheme.textMuted.opacity(0.7))
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $bio)
                                    .font(Theme.syne(15))
                                    .foregroundStyle(campusTheme.textPrimary)
                                    .tint(campusTheme.primary)
                                    .frame(minHeight: 96)
                                    .scrollContentBackground(.hidden)
                                    .onChange(of: bio) { newValue in
                                        if newValue.count > bioLimit {
                                            bio = String(newValue.prefix(bioLimit))
                                        }
                                    }
                            }
                            Text("\(bio.count)/\(bioLimit)")
                                .font(Theme.syne(12, weight: .medium))
                                .foregroundStyle(bio.count >= bioLimit ? Color.red : campusTheme.textMuted)
                        }
                        .padding(16)
                    }

                    EditProfileSectionHeader(title: "Thrift Filters", subtitle: "Shown on your profile")
                    EditProfileCard {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sizes")
                                    .font(Theme.syne(14, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                EditProfileFlowLayout(spacing: 8) {
                                    ForEach(sizeOptions) { size in
                                        EditProfileChip(label: size.label, selected: selectedSizes.contains(size.id)) {
                                            toggleSize(size.id)
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Styles")
                                    .font(Theme.syne(14, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                EditProfileFlowLayout(spacing: 8) {
                                    ForEach(styleOptions) { style in
                                        EditProfileChip(label: style.label, selected: selectedStyles.contains(style.id)) {
                                            toggleStyle(style.id)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }

                    EditProfileSectionHeader(title: "Profile Tags", subtitle: "Pick tags to show on your profile")
                    EditProfileCard {
                        VStack(alignment: .leading, spacing: 14) {
                            EditProfileFlowLayout(spacing: 8) {
                                ForEach(suggestedTags, id: \.self) { tag in
                                    let selected = selectedTags.contains(tag)
                                    EditProfileChip(label: tag, selected: selected) {
                                        toggleTag(tag)
                                    }
                                }
                            }

                            Text("\(selectedTags.count)/\(maxTags) tags")
                                .font(Theme.syne(11, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        .padding(16)
                    }

                    EditProfileSectionHeader(title: "Preferences", subtitle: "Control what appears on your profile")
                    EditProfileCard {
                        EditProfileRow(label: "Open to Trades") {
                            EditProfileIOSSwitch(isOn: $isTradesOpen)
                        }
                        EditProfileRow(label: "Show School Badge", showDivider: false) {
                            EditProfileIOSSwitch(isOn: $showBadge)
                        }
                    }

                    EditProfileSectionHeader(title: "Social Links", subtitle: "Connect accounts to show on your profile")
                    EditProfileCard {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                socialConnectButton(
                                    title: "Instagram",
                                    connected: instagramConnected,
                                    subtitle: instagramConnected && !instagram.isEmpty ? "@\(instagram)" : "Tap to connect",
                                    gradient: [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF")],
                                    glyph: "camera.fill"
                                ) {
                                    Task { await startInstagramConnect() }
                                }

                                socialConnectButton(
                                    title: "Depop",
                                    connected: !depop.isEmpty,
                                    subtitle: depop.isEmpty ? "Add handle" : "@\(depop)",
                                    gradient: [Color(hex: "#FF2300"), Color(hex: "#FF4D2E")],
                                    glyph: "bag.fill"
                                ) {
                                    pendingDepopHandle = depop
                                    showDepopSheet = true
                                }
                            }

                            if instagramConnected {
                                Button {
                                    InstagramConnectService.disconnect()
                                    instagramConnected = false
                                    instagram = ""
                                    Motion.haptic(.light)
                                } label: {
                                    Text("Disconnect Instagram")
                                        .font(Theme.syne(13, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#E11D48"))
                                }
                                .buttonStyle(.plain)
                            }

                            if let socialError {
                                Text(socialError)
                                    .font(Theme.syne(12))
                                    .foregroundStyle(Color(hex: "#E11D48"))
                            }
                        }
                        .padding(16)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(campusTheme.primary)
                    } else {
                        Text("save")
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                .disabled(isSaving)
            }
        }
        .campusPageStyle()
        .onChange(of: photoItem) { item in
            Task { await loadAndUploadPhoto(item) }
        }
        .alert("Could not save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .sheet(isPresented: $showInstagramAuthSheet) {
            instagramAuthorizeSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDepopSheet) {
            depopLinkSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            loadFromUser()
            loadLocalPreferences()
        }
    }

    private var instagramAuthorizeSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "camera.fill")
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("connect instagram")
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Authorize popup to link your Instagram.")
                        .font(Theme.syne(13))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }

            Text("After signing into Instagram, confirm your handle and allow the connection.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)

            HStack(spacing: 4) {
                Text("@")
                    .foregroundStyle(campusTheme.textMuted)
                TextField("yourhandle", text: $pendingInstagramHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(campusTheme.primary)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(campusTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))

            Button {
                let handle = pendingInstagramHandle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "@", with: "")
                guard !handle.isEmpty else { return }
                InstagramConnectService.saveConnection(handle: handle)
                instagram = handle
                instagramConnected = true
                showInstagramAuthSheet = false
                Motion.haptic(.medium)
            } label: {
                Text("Allow & Connect")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(pendingInstagramHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(pendingInstagramHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

            Button("Not now") {
                showInstagramAuthSheet = false
            }
            .font(Theme.syne(14, weight: .semibold))
            .foregroundStyle(campusTheme.textMuted)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(campusTheme.wash.ignoresSafeArea())
    }

    private var depopLinkSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("depop handle")
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            HStack(spacing: 4) {
                Text("@").foregroundStyle(campusTheme.textMuted)
                TextField("handle", text: $pendingDepopHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(campusTheme.primary)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(campusTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))

            Button {
                depop = pendingDepopHandle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "@", with: "")
                showDepopSheet = false
            } label: {
                Text("Save")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(campusTheme.wash.ignoresSafeArea())
    }

    private func socialConnectButton(
        title: String,
        connected: Bool,
        subtitle: String,
        gradient: [Color],
        glyph: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: glyph)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(subtitle)
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(connected ? campusTheme.primary : campusTheme.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(campusTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(connected ? campusTheme.primary.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }

    private func startInstagramConnect() async {
        socialError = nil
        isConnectingInstagram = true
        defer { isConnectingInstagram = false }
        do {
            try await InstagramConnectService.openInstagramLogin()
            pendingInstagramHandle = instagram
            showInstagramAuthSheet = true
        } catch {
            if let err = error as? InstagramConnectError, err == .cancelled {
                socialError = nil
            } else {
                socialError = error.localizedDescription
            }
            // Still offer authorize sheet so they can connect with a handle.
            pendingInstagramHandle = instagram
            showInstagramAuthSheet = true
        }
    }

    private func toggleTag(_ tag: String) {
        if let idx = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: idx)
        } else if selectedTags.count < maxTags {
            selectedTags.append(tag)
        }
        Motion.haptic(.light)
    }

    private var photoSection: some View {
        EditProfileCard {
            VStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let pickedPhoto {
                            Image(uiImage: pickedPhoto)
                                .resizable()
                                .scaledToFill()
                        } else {
                            AvatarView(
                                urlString: avatarURL,
                                size: 104,
                                cornerRadius: 30,
                                initials: name.isEmpty ? "U" : name
                            )
                        }
                    }
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: isUploadingPhoto ? "hourglass" : "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(campusTheme.primary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(campusTheme.surface, lineWidth: 2))
                    }
                    .disabled(isUploadingPhoto)
                    .offset(x: 6, y: 6)
                }

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Text(isUploadingPhoto ? "uploading…" : "change photo")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Capsule())
                }
                .disabled(isUploadingPhoto)
            }
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
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
        if let tags = d.array(forKey: EditProfilePrefs.tags) as? [String] {
            let allowed = Set(suggestedTags)
            selectedTags = tags.filter { allowed.contains($0) }
        }
        if d.object(forKey: EditProfilePrefs.tradesOpen) != nil {
            isTradesOpen = d.bool(forKey: EditProfilePrefs.tradesOpen)
        }
        if d.object(forKey: EditProfilePrefs.showBadge) != nil {
            showBadge = d.bool(forKey: EditProfilePrefs.showBadge)
        }
        instagram = InstagramConnectService.handle.isEmpty
            ? (d.string(forKey: EditProfilePrefs.instagram) ?? "")
            : InstagramConnectService.handle
        instagramConnected = InstagramConnectService.isConnected || !instagram.isEmpty
        depop = d.string(forKey: EditProfilePrefs.depop) ?? ""
    }

    private func saveLocalPreferences() {
        let d = UserDefaults.standard
        d.set(Array(selectedSizes), forKey: EditProfilePrefs.sizes)
        d.set(Array(selectedStyles), forKey: EditProfilePrefs.styles)
        d.set(selectedTags, forKey: EditProfilePrefs.tags)
        d.set(isTradesOpen, forKey: EditProfilePrefs.tradesOpen)
        d.set(showBadge, forKey: EditProfilePrefs.showBadge)
        d.set(instagram, forKey: EditProfilePrefs.instagram)
        d.set(depop, forKey: EditProfilePrefs.depop)
        if instagramConnected, !instagram.isEmpty {
            InstagramConnectService.saveConnection(handle: instagram)
        }
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
                        username: userName.isEmpty ? nil : userName,
                        first_name: firstName.isEmpty ? nil : firstName,
                        last_name: lastName.isEmpty ? nil : lastName,
                        bio: trimmedBio.isEmpty ? nil : trimmedBio,
                        shop_name: nil,
                        avatar_url: nil,
                        country: nil,
                        instagram_handle: (instagramConnected && !instagram.isEmpty) ? instagram : nil
                    )
                )
                authVM.user = updated
                dismiss()
            } catch {
                saveErrorMessage = error.localizedDescription
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

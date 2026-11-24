import PhotosUI
import Supabase
import SwiftUI
import UIKit

private enum OnboardingStep: Int, CaseIterable {
    case campusWelcome = 1
    case username
    case photo
    case style
    case tour
}

private let onboardingStyleOptions = [
    "Streetwear", "Vintage", "Y2K", "Cottagecore", "Minimalist", "Grunge", "Academia", "Sporty",
    "Preppy", "Skater", "Workwear", "Gorpcore", "Indie", "Retro", "Techwear", "Coquette",
    "Western", "Formal", "Boho", "Punk",
]

private enum OnboardingPrefs {
    static var styles: String { EditProfilePrefs.styles }
    static func requiredKey(userId: String) -> String { "popup.onboarding.required.\(userId)" }
}

// MARK: - Flow

struct OnboardingFlowView: View {
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var step: OnboardingStep = .campusWelcome
    @State private var username = ""
    @StateObject private var usernameCheck = UsernameAvailabilityChecker()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var selectedStyles: Set<String> = []
    @State private var localError: String?
    @State private var isSaving = false
    @State private var contentOpacity: Double = 1

    /// Onboarding is always drawn dark (white text over the aurora), so it uses the
    /// dark variant of the school theme whatever the phone's appearance is.
    private var campus: CampusTheme {
        CampusTheme.from(schoolName: authVM.user?.country, appearance: .dark)
    }

    var body: some View {
        ZStack {
            // One aurora behind every step (same as Home), so steps cross-fade over it.
            AuroraBackground()

            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .campusWelcome:
                        CampusWelcomeStep(campus: campus) {
                            advance(to: .username)
                        }
                    case .username:
                        usernameStep
                    case .photo:
                        photoStep
                    case .style:
                        styleStep
                    case .tour:
                        FeatureTourView(campus: campus) {
                            Task { await finishOnboarding() }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .opacity(contentOpacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .environment(\.campusTheme, campus)
    }

    // MARK: Username

    private var usernameStep: some View {
        onboardingChrome(
            title: "Pick a username",
            subtitle: "This is how other students will find you on popup.",
            primaryTitle: "Continue",
            canContinue: username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                && !usernameCheck.isTaken && !usernameCheck.isChecking,
            onContinue: { Task { await saveUsernameAndAdvance() } },
            showSkip: false
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
                HStack(spacing: 6) {
                    Text("@")
                        .foregroundStyle(Color.white.opacity(0.7))
                    TextField(
                        "",
                        text: $username,
                        prompt: Text("yourname").foregroundColor(Color.white.opacity(0.45))
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .tint(.white)
                    .onChange(of: username) { newValue in
                        localError = nil
                        usernameCheck.check(newValue.lowercased())
                    }
                    if usernameCheck.isChecking {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else if usernameCheck.status == .available {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "#6EE7A8"))
                    } else if usernameCheck.isTaken {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(hex: "#FF6B6B"))
                    }
                }
                .font(Theme.syne(16, weight: .medium))
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(Capsule().fill(campus.glassStrong))
                .overlay(
                    Capsule()
                        .stroke(usernameCheck.isTaken ? Color(hex: "#FF6B6B") : campus.border, lineWidth: 1)
                )
                if usernameCheck.isTaken, let message = usernameCheck.message {
                    Text(message)
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(Color(hex: "#FF6B6B"))
                }
            }
        }
    }

    // MARK: Photo

    private var photoStep: some View {
        onboardingChrome(
            title: "Add a profile pic",
            subtitle: "Add a photo to continue, or skip for now.",
            primaryTitle: photoImage == nil ? "Continue" : "Use this photo",
            canContinue: photoImage != nil,
            onContinue: { Task { await savePhotoAndAdvance() } },
            showSkip: true,
            onSkip: { advance(to: .style) }
        ) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(campus.glassStrong)
                        .frame(width: 140, height: 140)
                        .overlay(Circle().stroke(campus.border, lineWidth: 1))
                    if let photoImage {
                        Image(uiImage: photoImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 140)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(campus.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(photoImage == nil ? "Choose photo" : "Change photo", systemImage: "photo.on.rectangle")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campus.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(campus.glass))
                        .overlay(Capsule().stroke(campus.border, lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                .onChange(of: selectedPhoto) { item in
                    Task { await loadPhoto(item) }
                }
            }
        }
    }

    // MARK: Style

    private var styleStep: some View {
        onboardingChrome(
            title: "What’s your style?",
            subtitle: "We’ll use this to personalize what you see.",
            primaryTitle: isSaving ? "Saving…" : "Continue",
            canContinue: true,
            onContinue: { Task { await saveStylesAndStartTour() } },
            showSkip: true,
            onSkip: { Task { await saveStylesAndStartTour() } }
        ) {
            ScrollView(showsIndicators: false) {
                FlowChipGrid(
                    options: onboardingStyleOptions,
                    selection: $selectedStyles,
                    accent: campus.primary,
                    campusTheme: true
                )
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Shared chrome

    private func onboardingChrome<Content: View>(
        title: String,
        subtitle: String,
        primaryTitle: String,
        canContinue: Bool,
        onContinue: @escaping () -> Void,
        showSkip: Bool,
        onSkip: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            onboardingHeader
                .padding(.top, 12)

            // Same left-aligned header as Home's "discover / campus thrift finds".
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.syne(30, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.top, 28)

            Spacer(minLength: 20)

            VStack(spacing: 14) {
                if let localError {
                    Text(localError)
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(Color(hex: "#FF6B6B"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Motion.haptic(.medium)
                    onContinue()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(PopupBrand.buttonText)
                        } else {
                            Text(primaryTitle)
                        }
                    }
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(PopupBrand.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(PopupBrand.button))
                    .shadow(color: Color.white.opacity(canContinue ? 0.16 : 0), radius: 14, y: 8)
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                .opacity(canContinue && !isSaving ? 1 : 0.45)
                .disabled(!canContinue || isSaving)

                if showSkip, let onSkip {
                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(Theme.syne(14, weight: .medium))
                            .foregroundStyle(campus.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                    .disabled(isSaving)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    /// "popup" on the left, the three setup steps from the welcome screen as a
    /// glass progress pill on the right.
    private var onboardingHeader: some View {
        HStack(alignment: .center) {
            Text("popup")
                .font(Theme.syne(22, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(campus.textPrimary)
            Spacer()
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(OnboardingStep.username.rawValue...OnboardingStep.style.rawValue, id: \.self) { i in
                        Capsule()
                            .fill(i <= step.rawValue ? campus.textPrimary : campus.textPrimary.opacity(0.22))
                            .frame(width: i == step.rawValue ? 18 : 7, height: 7)
                    }
                }
                Text("\(step.rawValue - 1) of \(OnboardingStep.style.rawValue - 1)")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(campus.glass))
            .overlay(Capsule().stroke(campus.border, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue - 1) of \(OnboardingStep.style.rawValue - 1)")
        }
    }

    // MARK: Actions

    private func advance(to next: OnboardingStep) {
        localError = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            step = next
            withAnimation(.easeInOut(duration: 0.35)) {
                contentOpacity = 1
            }
        }
    }

    private func saveUsernameAndAdvance() async {
        localError = nil
        let trimmed = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard trimmed.count >= 3 else {
            localError = "Username needs at least 3 characters."
            return
        }

        isSaving = true
        defer { isSaving = false }

        if await usernameCheck.checkNow(trimmed) == .taken {
            localError = "@\(trimmed) is taken. Pick a new one."
            return
        }

        guard let client = await SupabaseManager.shared.clientWithValidSession() else {
            // Offline / legacy — still continue with local preference.
            advance(to: .photo)
            return
        }

        do {
            let updated = try await SupabaseProfileService.updateProfile(
                client: client,
                patch: .init(username: trimmed)
            )
            authVM.user = updated
            advance(to: .photo)
        } catch {
            localError = SupabaseProfileService.friendlySaveError(error)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            photoImage = image
        }
    }

    private func savePhotoAndAdvance() async {
        localError = nil
        guard let photoImage else {
            advance(to: .style)
            return
        }

        isSaving = true
        defer { isSaving = false }

        guard let client = await SupabaseManager.shared.clientWithValidSession(),
              let data = photoImage.jpegData(compressionQuality: 0.82) else {
            advance(to: .style)
            return
        }

        do {
            let uid = try await client.auth.session.user.id.uuidString.lowercased()
            let path = "\(uid)/avatar-\(UUID().uuidString.lowercased()).jpg"
            let opts = FileOptions(contentType: "image/jpeg", upsert: true)
            try await client.storage.from("product-images").upload(path, data: data, options: opts)
            let url = try client.storage.from("product-images").getPublicURL(path: path)
            let updated = try await SupabaseProfileService.updateProfile(
                client: client,
                patch: .init(avatar_url: url.absoluteString)
            )
            authVM.user = updated
            advance(to: .style)
        } catch {
            localError = "Couldn’t upload photo — you can skip or try again."
        }
    }

    private func saveStylesAndStartTour() async {
        isSaving = true
        defer { isSaving = false }
        UserDefaults.standard.set(Array(selectedStyles), forKey: OnboardingPrefs.styles)
        advance(to: .tour)
    }

    private func finishOnboarding() async {
        isSaving = true
        defer { isSaving = false }
        UserDefaults.standard.set(Array(selectedStyles), forKey: OnboardingPrefs.styles)
        withAnimation(.easeInOut(duration: 0.55)) {
            contentOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        authVM.completeOnboarding()
    }
}

// MARK: - Campus welcome (loading beat → Home-style welcome)

/// First screen a new account sees. Same aurora + glass look as Home: a big
/// left-aligned "welcome" header (like Home's "discover"), the campus badge, and
/// glass rows previewing the short setup so people know what's next.
private struct CampusWelcomeStep: View {
    let campus: CampusTheme
    let onContinue: () -> Void

    private enum Phase {
        case loading
        case welcome
    }

    private struct SetupRow: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let rows = [
        SetupRow(id: 1, title: "Pick a username", detail: "10 sec"),
        SetupRow(id: 2, title: "Add a photo", detail: "optional"),
        SetupRow(id: 3, title: "Choose your style", detail: "optional"),
    ]

    @State private var phase: Phase = .loading
    @State private var loadingOpacity: Double = 0
    @State private var headerShown = false
    @State private var rowsShown = 0
    @State private var continueShown = false

    var body: some View {
        ZStack {
            if phase == .loading {
                loadingContent
                    .opacity(loadingOpacity)
            } else {
                welcomeContent
            }
        }
        .onAppear(perform: runSequence)
    }

    private var loadingContent: some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(campus.textPrimary)
                .scaleEffect(1.1)
                .frame(width: 62, height: 62)
                .background(campus.glass)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(campus.border, lineWidth: 1)
                )

            Text("Setting up your campus…")
                .font(Theme.syne(15, weight: .medium))
                .foregroundStyle(campus.textMuted)
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("popup")
                    .font(Theme.syne(22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(campus.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                campusBadge
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("welcome")
                    .font(Theme.syne(36, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Text("to \(campus.shortName) campus thrift")
                    .font(Theme.syne(24, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 40)
            .accessibilityElement(children: .combine)
            .opacity(headerShown ? 1 : 0)
            .offset(y: headerShown ? 0 : 14)

            Spacer(minLength: 24)

            Text("3 quick steps")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
                .padding(.bottom, 12)
                .opacity(rowsShown > 0 ? 1 : 0)

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    setupRow(row)
                        .opacity(rowsShown >= row.id ? 1 : 0)
                        .offset(y: rowsShown >= row.id ? 0 : 16)
                }
            }

            Button {
                Motion.haptic(.medium)
                onContinue()
            } label: {
                Text("Let’s go")
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(PopupBrand.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(PopupBrand.button))
                    .shadow(color: Color.white.opacity(0.16), radius: 14, y: 8)
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            .padding(.top, 22)
            .opacity(continueShown ? 1 : 0)
            .disabled(!continueShown)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    /// Same glass square as Home's campus badge (dot over the school's short name).
    private var campusBadge: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(campus.secondary)
                .frame(width: 6, height: 6)
            Text(campus.shortName)
                .font(Theme.syne(13, weight: .black))
                .tracking(0.6)
                .foregroundStyle(campus.tint)
        }
        .frame(width: 52, height: 52)
        .background(campus.glassStrong)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(campus.glass)
        )
        .accessibilityLabel("\(campus.shortName) popup campus")
    }

    private func setupRow(_ row: SetupRow) -> some View {
        HStack(spacing: 12) {
            Text("\(row.id)")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campus.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(campus.glassInset))
                .overlay(Circle().stroke(campus.border, lineWidth: 1))
            Text(row.title)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(row.detail)
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campus.textMuted)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(campus.glass)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(campus.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func runSequence() {
        withAnimation(.easeInOut(duration: 0.45)) {
            loadingOpacity = 1
        }

        // Brief loading beat, then the welcome builds in: header, steps, button.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeInOut(duration: 0.35)) {
                loadingOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                phase = .welcome
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    headerShown = true
                }
                for i in 1...rows.count {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25 + Double(i) * 0.09)) {
                        rowsShown = i
                    }
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.75)) {
                    continueShown = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Motion.haptic(.medium)
                }
            }
        }
    }
}

// MARK: - Chip grid

private struct FlowChipGrid: View {
    let options: [String]
    @Binding var selection: Set<String>
    var accent: Color
    var campusTheme: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(options, id: \.self) { option in
                let selected = selection.contains(option)
                Button {
                    Motion.haptic(.light)
                    if selected {
                        selection.remove(option)
                    } else {
                        selection.insert(option)
                    }
                } label: {
                    Text(option)
                        .font(Theme.syne(13, weight: .semibold))
                        // "Cottagecore" otherwise breaks mid-word in a three-column grid.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(chipForeground(selected: selected))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(chipFill(selected: selected)))
                        .overlay(Capsule().stroke(chipStroke(selected: selected), lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
    }

    private func chipForeground(selected: Bool) -> Color {
        if campusTheme {
            return selected ? PopupBrand.buttonText : .white
        }
        return selected ? .white : PopupBrand.textPrimary
    }

    private func chipFill(selected: Bool) -> Color {
        if campusTheme {
            return selected ? .white : Color.white.opacity(0.07)
        }
        return selected ? accent : PopupBrand.surface
    }

    private func chipStroke(selected: Bool) -> Color {
        if campusTheme {
            return selected ? .white : Color.white.opacity(0.12)
        }
        return selected ? accent : PopupBrand.border
    }
}

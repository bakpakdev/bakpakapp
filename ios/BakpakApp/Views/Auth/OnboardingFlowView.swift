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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var selectedStyles: Set<String> = []
    @State private var localError: String?
    @State private var isSaving = false
    @State private var contentOpacity: Double = 1

    private var campus: CampusTheme {
        CampusTheme.from(schoolName: authVM.user?.country)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

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
    }

    private var background: some View {
        Group {
            if step == .campusWelcome || step == .tour {
                Color.clear
            } else {
                CampusGlowBackground(campus: campus)
            }
        }
    }

    // MARK: Username

    private var usernameStep: some View {
        onboardingChrome(
            title: "Pick a username",
            subtitle: "This is how other students will find you on popup.",
            primaryTitle: "Continue",
            canContinue: username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3,
            onContinue: { Task { await saveUsernameAndAdvance() } },
            showSkip: false
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
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
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
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
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 140, height: 140)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    if let photoImage {
                        Image(uiImage: photoImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 140)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text(photoImage == nil ? "Choose photo" : "Change photo")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campus.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                        )
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
            PopupWordmark(scale: .header, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(Theme.syne(26, weight: .black))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()

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
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PopupBrand.button)
                    )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                .opacity(canContinue && !isSaving ? 1 : 0.45)
                .disabled(!canContinue || isSaving)

                if showSkip, let onSkip {
                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(Theme.syne(14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                    .disabled(isSaving)
                }

                if let localError {
                    Text(localError)
                        .font(Theme.syne(12))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            if step != .tour {
                Text("Step \(step.rawValue) of \(OnboardingStep.style.rawValue)")
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
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
            localError = error.localizedDescription
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

// MARK: - Campus welcome (auto loading → logo swipe → welcome)

private struct CampusWelcomeStep: View {
    let campus: CampusTheme
    let onContinue: () -> Void

    private enum Phase {
        case loading
        case welcome
    }

    @State private var phase: Phase = .loading
    @State private var loadingOpacity: Double = 0
    @State private var welcomeOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.88
    @State private var logoOpacity: Double = 0
    @State private var copyOpacity: Double = 0
    @State private var continueOpacity: Double = 0

    var body: some View {
        ZStack {
            CampusGlowBackground(campus: campus, strength: glowOpacity)

            if phase == .loading {
                loadingContent
                    .opacity(loadingOpacity)
            }

            if phase == .welcome {
                welcomeContent
                    .opacity(welcomeOpacity)
            }
        }
        .onAppear(perform: runSequence)
    }

    private var loadingContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(PopupBrand.textPrimary)
                .scaleEffect(1.15)

            Text("Setting up your campus…")
                .font(Theme.syne(15, weight: .medium))
                .foregroundStyle(PopupBrand.textMuted)
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer()

            PopupWordmark(scale: .hero)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

            VStack(spacing: 10) {
                Text(campus.welcomeTitle)
                    .font(Theme.syne(26, weight: .black))
                    .foregroundStyle(PopupBrand.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Text("Let’s finish setting up your profile.")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(PopupBrand.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 22)
            .opacity(copyOpacity)

            Spacer()

            Button {
                Motion.haptic(.medium)
                onContinue()
            } label: {
                Text("Continue")
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(PopupBrand.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PopupBrand.button)
                    )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(continueOpacity)
        }
    }

    private func runSequence() {
        withAnimation(.easeInOut(duration: 0.45)) {
            loadingOpacity = 1
        }

        // Brief loading beat, then transition into the welcome animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                phase = .welcome
                withAnimation(.easeInOut(duration: 0.35)) {
                    welcomeOpacity = 1
                    glowOpacity = 0.55
                }

                withAnimation(.spring(response: 0.62, dampingFraction: 0.78).delay(0.08)) {
                    logoScale = 1.04
                    logoOpacity = 1
                    glowOpacity = 1
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72).delay(0.42)) {
                    logoScale = 1
                }
                withAnimation(.easeOut(duration: 0.4).delay(0.55)) {
                    copyOpacity = 1
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.85)) {
                    continueOpacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
                        .foregroundStyle(chipForeground(selected: selected))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(chipFill(selected: selected))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(chipStroke(selected: selected), lineWidth: 1)
                        )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
    }

    private func chipForeground(selected: Bool) -> Color {
        if campusTheme {
            return selected ? accent : .white
        }
        return selected ? .white : PopupBrand.textPrimary
    }

    private func chipFill(selected: Bool) -> Color {
        if campusTheme {
            return selected ? .white : Color.white.opacity(0.14)
        }
        return selected ? accent : PopupBrand.surface
    }

    private func chipStroke(selected: Bool) -> Color {
        if campusTheme {
            return selected ? .white : Color.white.opacity(0.28)
        }
        return selected ? accent : PopupBrand.border
    }
}

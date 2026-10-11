import SwiftUI

// MARK: - Campus options (Oregon only for now)

private struct CampusSchool: Identifiable, Hashable {
    let id: String
    let name: String
    let emailDomain: String

    static let all: [CampusSchool] = [
        CampusSchool(id: "uo", name: "University of Oregon", emailDomain: "uoregon.edu"),
        CampusSchool(id: "osu", name: "Oregon State University", emailDomain: "oregonstate.edu"),
    ]
}

private enum RegisterStep: Int, CaseIterable {
    case name = 1
    case school
    case email
    case verify
    case password
}

// MARK: - Multi-step register

struct RegisterView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var showRegister: Bool
    let onBackToWelcome: () -> Void

    @State private var step: RegisterStep = .name
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedSchool: CampusSchool?
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var localError: String?
    @State private var statusMessage: String?

    private var canContinue: Bool {
        switch step {
        case .name:
            return !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .school:
            return selectedSchool != nil
        case .email:
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.contains("@") && trimmed.hasSuffix(".edu")
        case .verify:
            // Continue only after they opened the email link AND tapped Confirm email.
            return authVM.hasVerifiedSignupEmail
        case .password:
            return password.count >= 6 && password == confirmPassword
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .email: return "Send verification email"
        case .verify:
            if authVM.hasVerifiedSignupEmail { return "Continue" }
            if authVM.emailConfirmationLinkOpened { return "Confirm email" }
            return "Waiting for email link…"
        case .password: return "Create account"
        default: return "Continue"
        }
    }

    var body: some View {
        AuthScreenChrome(onBack: handleBack) {
            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 24) {
                stepHeader

                Group {
                    switch step {
                    case .name: nameStep
                    case .school: schoolStep
                    case .email: emailStep
                    case .verify: verifyStep
                    case .password: passwordStep
                    }
                }

                AuthPrimaryButton {
                    advanceOrSubmit()
                } label: {
                    if authVM.isLoading && (step == .email || step == .verify || step == .password) {
                        ProgressView()
                    } else {
                        Text(primaryButtonTitle)
                    }
                }
                .opacity(verifyPrimaryEnabled || authVM.isLoading ? 1 : 0.45)
                .disabled(!verifyPrimaryEnabled || authVM.isLoading)

                if step == .verify && !authVM.hasVerifiedSignupEmail {
                    Text(
                        authVM.emailConfirmationLinkOpened
                            ? "Link opened — tap Confirm email to continue."
                            : "Open the email on this phone, tap Open popup & confirm, then come back here."
                    )
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(PopupBrand.textMuted)
                }

                if let message = statusMessage, step == .verify || step == .email {
                    Text(message)
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(PopupBrand.textMuted)
                }

                if let error = localError ?? authVM.errorMessage {
                    Text(error)
                        .font(Theme.syne(12))
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.leading)
                }

                if step == .password {
                    Button {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            showRegister = false
                        }
                    } label: {
                        Text("Already have an account? Log in")
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(PopupBrand.textMuted)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            Text("Step \(step.rawValue) of \(RegisterStep.allCases.count)")
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(PopupBrand.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            if authVM.isAwaitingEmailVerification {
                if let pending = authVM.pendingVerificationEmail,
                   email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    email = pending
                }
                step = .verify
            }
        }
        .onChange(of: authVM.emailConfirmationLinkOpened) { opened in
            guard opened, step == .verify, !authVM.hasVerifiedSignupEmail else { return }
            statusMessage = "Email link opened — tap Confirm email."
            Motion.haptic(.medium)
        }
        .onChange(of: authVM.hasVerifiedSignupEmail) { verified in
            guard verified, step == .verify else { return }
            statusMessage = "Email confirmed — tap Continue to create your password."
            Motion.haptic(.medium)
        }
        .task(id: step) {
            guard step == .verify else { return }
            while !Task.isCancelled && step == .verify && !authVM.emailConfirmationLinkOpened {
                await authVM.pollSignupEmailLinkStatus()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    /// Primary CTA: disabled while waiting for the email link; enabled for Confirm / Continue / other steps.
    private var verifyPrimaryEnabled: Bool {
        switch step {
        case .verify:
            return authVM.emailConfirmationLinkOpened || authVM.hasVerifiedSignupEmail
        default:
            return canContinue
        }
    }

    // MARK: Header

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.syne(26, weight: .black))
                .foregroundStyle(PopupBrand.textPrimary)

            Text(subtitle)
                .font(Theme.syne(14, weight: .medium))
                .foregroundStyle(PopupBrand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch step {
        case .name: return "What's your name?"
        case .school: return "Pick your school"
        case .email: return "School email"
        case .verify: return "Verify your email address"
        case .password: return "Create a password"
        }
    }

    private var subtitle: String {
        switch step {
        case .name:
            return "We’ll use this on your popup profile so other students know who they’re buying from."
        case .school:
            return "Right now popup is only available for University of Oregon and Oregon State students."
        case .email:
            if let school = selectedSchool {
                return "Enter your \(school.name) email ending in @\(school.emailDomain). We’ll send a verification link there."
            }
            return "Enter your college email (.edu). We’ll send a verification link."
        case .verify:
            if authVM.hasVerifiedSignupEmail {
                return "You’re confirmed. Tap Continue to create your password."
            }
            if authVM.emailConfirmationLinkOpened {
                return "We got you back into popup. Tap Confirm email to unlock the rest of signup."
            }
            return "We sent a link to \(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()). Open it on this phone — it brings you into popup — then tap Confirm email."
        case .password:
            return "Choose a password with at least 6 characters. You’ll use this to sign in next time."
        }
    }

    // MARK: Steps

    private var nameStep: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("First name")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                TextField(
                    "",
                    text: $firstName,
                    prompt: Text("First name").foregroundColor(PopupBrand.textMuted)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundColor(PopupBrand.textPrimary)
                .authFieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Last name")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                TextField(
                    "",
                    text: $lastName,
                    prompt: Text("Last name").foregroundColor(PopupBrand.textMuted)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundColor(PopupBrand.textPrimary)
                .authFieldStyle()
            }
        }
    }

    private var schoolStep: some View {
        VStack(spacing: 8) {
            ForEach(CampusSchool.all) { school in
                Button {
                    Motion.haptic(.light)
                    selectedSchool = school
                    localError = nil
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(school.name)
                                .font(Theme.syne(15, weight: .semibold))
                                .foregroundStyle(PopupBrand.textPrimary)
                            Text("@\(school.emailDomain)")
                                .font(Theme.syne(12, weight: .medium))
                                .foregroundStyle(PopupBrand.textMuted)
                        }
                        Spacer(minLength: 0)
                        if selectedSchool == school {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(PopupBrand.textPrimary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedSchool == school ? PopupBrand.field : PopupBrand.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selectedSchool == school ? PopupBrand.textPrimary.opacity(0.35) : PopupBrand.border,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("College email")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
            TextField(
                "",
                text: $email,
                prompt: Text(selectedSchool.map { "name@\($0.emailDomain)" } ?? "name@school.edu")
                    .foregroundColor(PopupBrand.textMuted)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .foregroundColor(PopupBrand.textPrimary)
            .authFieldStyle()
        }
    }

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: verifyStatusIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(verifyStatusColor)
                Text(verifyStatusText)
                    .font(Theme.syne(14, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PopupBrand.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PopupBrand.border, lineWidth: 1)
            )

            Button {
                Task { await resendVerificationEmail() }
            } label: {
                Text(authVM.isLoading ? "Sending…" : "Resend verification email")
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(PopupBrand.textMuted)
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
            .disabled(authVM.isLoading || authVM.hasVerifiedSignupEmail)
        }
    }

    private var verifyStatusIcon: String {
        if authVM.hasVerifiedSignupEmail { return "checkmark.seal.fill" }
        if authVM.emailConfirmationLinkOpened { return "envelope.open.fill" }
        return "envelope.badge"
    }

    private var verifyStatusColor: Color {
        if authVM.hasVerifiedSignupEmail { return Color(hex: "#22C55E") }
        if authVM.emailConfirmationLinkOpened { return PopupBrand.textPrimary }
        return PopupBrand.textMuted
    }

    private var verifyStatusText: String {
        if authVM.hasVerifiedSignupEmail { return "Email confirmed" }
        if authVM.emailConfirmationLinkOpened { return "Link opened — confirm below" }
        return "Waiting for you to open the email"
    }

    private var passwordStep: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: Text("Password").foregroundColor(PopupBrand.textMuted))
                        } else {
                            SecureField("", text: $password, prompt: Text("Password").foregroundColor(PopupBrand.textMuted))
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(PopupBrand.textPrimary)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PopupBrand.textMuted)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .authFieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm password")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                HStack(spacing: 8) {
                    Group {
                        if showConfirmPassword {
                            TextField("", text: $confirmPassword, prompt: Text("Confirm password").foregroundColor(PopupBrand.textMuted))
                        } else {
                            SecureField("", text: $confirmPassword, prompt: Text("Confirm password").foregroundColor(PopupBrand.textMuted))
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(PopupBrand.textPrimary)

                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PopupBrand.textMuted)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .authFieldStyle()
            }
        }
    }

    // MARK: Navigation

    private func handleBack() {
        localError = nil
        statusMessage = nil
        authVM.errorMessage = nil
        switch step {
        case .name:
            onBackToWelcome()
        case .school:
            withAnimation(.easeInOut(duration: 0.3)) { step = .name }
        case .email:
            withAnimation(.easeInOut(duration: 0.3)) { step = .school }
        case .verify:
            authVM.clearSignupVerificationState()
            withAnimation(.easeInOut(duration: 0.3)) { step = .email }
        case .password:
            withAnimation(.easeInOut(duration: 0.3)) { step = .verify }
        }
    }

    private func advanceOrSubmit() {
        localError = nil
        authVM.errorMessage = nil
        statusMessage = nil

        switch step {
        case .name:
            guard canContinue else {
                localError = "Enter your first and last name."
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) { step = .school }

        case .school:
            guard selectedSchool != nil else {
                localError = "Pick your school to continue."
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) { step = .email }

        case .email:
            Task { await sendVerificationAndAdvance() }

        case .verify:
            if !authVM.hasVerifiedSignupEmail {
                guard authVM.emailConfirmationLinkOpened else {
                    localError = "Open the link in your popup email first."
                    return
                }
                Task { await confirmEmailInApp() }
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) { step = .password }

        case .password:
            guard password.count >= 6 else {
                localError = "Password must be at least 6 characters."
                return
            }
            guard password == confirmPassword else {
                localError = "Passwords don’t match."
                return
            }
            Task { await submitRegistration() }
        }
    }

    private func sendVerificationAndAdvance() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.hasSuffix(".edu") else {
            localError = "Use a valid college email ending in .edu."
            return
        }
        guard let school = selectedSchool else {
            localError = "Pick your school first."
            return
        }
        let domain = trimmed.split(separator: "@").last.map(String.init) ?? ""
        guard domain == school.emailDomain else {
            localError = "That email doesn’t match \(school.name). Use an @\(school.emailDomain) address."
            return
        }

        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = makeUsername(first: first, last: last)

        let ok = await authVM.sendSignupVerificationEmail(
            email: trimmed,
            username: username,
            firstName: first,
            lastName: last,
            school: school.name
        )
        guard ok else { return }

        statusMessage = "If you don’t see it in a minute, check spam — or tap Resend."
        withAnimation(.easeInOut(duration: 0.3)) { step = .verify }
    }

    private func resendVerificationEmail() async {
        localError = nil
        authVM.errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            localError = "Enter your school email first."
            return
        }

        let ok = await authVM.resendSignupVerificationEmail(email: trimmed)
        if ok {
            statusMessage = "New verification email sent — check inbox and spam."
        }
    }

    private func confirmEmailInApp() async {
        localError = nil
        authVM.errorMessage = nil
        let ok = await authVM.confirmSignupEmailInApp()
        if ok {
            statusMessage = "Email confirmed — create your password next."
            withAnimation(.easeInOut(duration: 0.3)) { step = .password }
        } else if let message = authVM.errorMessage {
            localError = message
        }
    }

    private func submitRegistration() async {
        guard let school = selectedSchool else { return }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        await authVM.completeSignupWithPassword(
            password: password,
            firstName: first,
            lastName: last,
            school: school.name
        )
    }

    private func makeUsername(first: String, last: String) -> String {
        let raw = (first + last)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        if raw.count >= 3 { return String(raw.prefix(24)) }
        if !raw.isEmpty { return String((raw + "user").prefix(24)) }
        return "student\(Int.random(in: 100...999))"
    }
}

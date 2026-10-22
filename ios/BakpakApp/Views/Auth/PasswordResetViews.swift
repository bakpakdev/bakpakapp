import SwiftUI

// MARK: - Forgot password (request the email)

struct ForgotPasswordSheet: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @State private var sentMessage: String?

    var body: some View {
        ZStack {
            PopupBrand.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("Reset password")
                    .font(Theme.syne(26, weight: .black))
                    .foregroundStyle(PopupBrand.textPrimary)

                if let sentMessage {
                    Text(sentMessage)
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(PopupBrand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Open the link on this phone. It works for 30 minutes.")
                        .font(Theme.syne(13))
                        .foregroundStyle(PopupBrand.textMuted)

                    AuthPrimaryButton {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                } else {
                    Text("Enter your college email and we’ll send you a link to pick a new password.")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(PopupBrand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(
                        "",
                        text: $email,
                        prompt: Text(verbatim: "name@school.edu").foregroundColor(PopupBrand.textMuted)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .foregroundColor(PopupBrand.textPrimary)
                    .authFieldStyle()

                    AuthPrimaryButton {
                        Task { sentMessage = await authVM.requestPasswordReset(email: email) }
                    } label: {
                        if authVM.isLoading {
                            ProgressView()
                        } else {
                            Text("Send reset link")
                        }
                    }

                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(Theme.syne(12))
                            .foregroundStyle(Color.red)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .onAppear { authVM.errorMessage = nil }
        .onDisappear { authVM.errorMessage = nil }
    }
}

// MARK: - Set a new password (opened from the email link)

struct SetNewPasswordView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState

    @State private var password = ""
    @State private var confirm = ""
    @State private var showPassword = false

    private var matches: Bool { !confirm.isEmpty && password == confirm }
    private var canSubmit: Bool { AuthViewModel.passwordMeetsRules(password) && matches && !authVM.isLoading }

    var body: some View {
        ZStack {
            PopupBrand.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("New password")
                            .font(Theme.syne(26, weight: .black))
                            .foregroundStyle(PopupBrand.textPrimary)
                        Spacer()
                        Button("Cancel") {
                            authVM.errorMessage = nil
                            authVM.pendingPasswordResetToken = nil
                        }
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(PopupBrand.textMuted)
                    }

                    Text("Pick a new password for popup. You’ll be signed in with it right after.")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(PopupBrand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    passwordField("New password", text: $password)
                    passwordField("Confirm new password", text: $confirm)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(AuthViewModel.passwordRules) { rule in
                            ruleRow(rule.label, met: rule.isMet(password))
                        }
                        ruleRow("Both passwords match", met: matches)
                    }

                    AuthPrimaryButton {
                        Task {
                            appState.path = []
                            await authVM.completePasswordReset(newPassword: password)
                        }
                    } label: {
                        if authVM.isLoading {
                            ProgressView()
                        } else {
                            Text("Save and sign in")
                        }
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.45)

                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(Theme.syne(12))
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
        }
        .onAppear { authVM.errorMessage = nil }
    }

    private func passwordField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Group {
                if showPassword {
                    TextField("", text: text, prompt: Text(placeholder).foregroundColor(PopupBrand.textMuted))
                } else {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundColor(PopupBrand.textMuted))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.newPassword)
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

    private func ruleRow(_ label: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(met ? Color(hex: "#22C55E") : PopupBrand.textMuted)
            Text(label)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(met ? PopupBrand.textPrimary : PopupBrand.textMuted)
        }
    }
}

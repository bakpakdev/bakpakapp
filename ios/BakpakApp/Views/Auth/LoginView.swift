import SwiftUI

// MARK: - Sign-in screen

struct PopupLanding: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var showRegister: Bool
    let onBack: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false

    var body: some View {
        AuthScreenChrome(onBack: onBack) {
            Spacer(minLength: 32)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in")
                        .font(Theme.syne(26, weight: .black))
                        .foregroundStyle(PopupBrand.textPrimary)

                    Text("popup is a marketplace for college students only. You need a college email (.edu) to access the app — if you don't have one yet, you won't be able to sign in.")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(PopupBrand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("College email")
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                        TextField(
                            "",
                            text: $email,
                            prompt: Text("name@school.edu")
                                .foregroundColor(PopupBrand.textMuted)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .foregroundColor(PopupBrand.textMuted)
                        .tint(PopupBrand.textMuted)
                        .authFieldStyle()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                        HStack(spacing: 8) {
                            Group {
                                if showPassword {
                                    TextField("Password", text: $password)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

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

                    if !authVM.usesSupabase {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API server")
                                .font(Theme.syne(13, weight: .semibold))
                                .foregroundStyle(PopupBrand.textPrimary.opacity(0.92))
                            TextField("http://127.0.0.1:5001/api", text: $authVM.baseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .authFieldStyle()
                            Text("Use your Mac's IP on device (e.g. http://192.168.1.20:5001/api). Must end with /api.")
                                .font(Theme.syne(11))
                                .foregroundStyle(PopupBrand.textMuted)
                        }
                    }

                    AuthPrimaryButton {
                        Task {
                            if !authVM.usesSupabase { authVM.applyServerURL() }
                            await authVM.login(email: email, password: password)
                        }
                    } label: {
                        if authVM.isLoading {
                            ProgressView()
                        } else {
                            Text("Continue")
                        }
                    }
                    .padding(.top, 4)

                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(Theme.syne(12))
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.leading)
                    }

                    Button {
                        showRegister = true
                    } label: {
                        Text("Need an account? Register")
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

            Text("By continuing, you agree to our Terms & Privacy Policy.")
                .font(Theme.syne(11))
                .foregroundStyle(PopupBrand.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

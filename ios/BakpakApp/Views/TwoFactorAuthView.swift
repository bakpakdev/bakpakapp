import SwiftUI
import UIKit

struct TwoFactorAuthView: View {
    @Environment(\.campusTheme) private var campusTheme
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var enabled = AccountPrefsStore.twoFactorEnabled
    @State private var backupCodes: [String] = AccountPrefsStore.twoFactorBackupCodes
    @State private var showEnableSheet = false
    @State private var showDisableConfirm = false
    @State private var copied = false

    private var emailLabel: String {
        let email = authVM.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "your campus email" : email
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    CampusPageHeader(title: "two-factor", subtitle: "extra lock on your account")

                    statusCard
                    howItWorksCard

                    if enabled {
                        backupCard
                    }

                    Button {
                        Motion.haptic(.medium)
                        if enabled {
                            showDisableConfirm = true
                        } else {
                            backupCodes = AccountPrefsStore.generateBackupCodes()
                            showEnableSheet = true
                        }
                    } label: {
                        Text(enabled ? "turn off two-factor" : "turn on two-factor")
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(enabled ? Color(hex: "#E11D48") : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(enabled ? campusTheme.surface : campusTheme.primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(enabled ? Color(hex: "#E11D48").opacity(0.25) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .campusPageStyle()
        .sheet(isPresented: $showEnableSheet) {
            enableSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Turn off two-factor?", isPresented: $showDisableConfirm, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) {
                enabled = false
                AccountPrefsStore.twoFactorEnabled = false
                AccountPrefsStore.twoFactorBackupCodes = []
                backupCodes = []
                Motion.haptic(.medium)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will only need your password to sign in.")
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: enabled ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(enabled ? Color.white : campusTheme.textPrimary)
                .frame(width: 52, height: 52)
                .background(enabled ? campusTheme.primary : campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(enabled ? "on" : "off")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(enabled
                     ? "Codes go to \(emailLabel) when you sign in on a new device."
                     : "Add a code after your password so a stolen password isn’t enough.")
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("how it works")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            bullet("popup emails a 6-digit code to \(emailLabel).")
            bullet("You enter that code after your password.")
            bullet("Save backup codes in case you lose email access.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(campusTheme.primary)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
        }
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("backup codes")
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                Button {
                    UIPasteboard.general.string = backupCodes.joined(separator: "\n")
                    copied = true
                    Motion.haptic(.light)
                } label: {
                    Text(copied ? "copied" : "copy")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(backupCodes, id: \.self) { code in
                    Text(code)
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Text("Each code works once. Store them somewhere private.")
                .font(Theme.syne(12))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(16)
        .background(CampusCardBackground())
    }

    private var enableSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("save these codes")
                .font(Theme.syne(28, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("You’ll need one if you can’t get email codes. Copy them before you turn two-factor on.")
                .font(Theme.syne(15))
                .foregroundStyle(campusTheme.textMuted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(backupCodes, id: \.self) { code in
                    Text(code)
                        .font(Theme.syne(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Button {
                UIPasteboard.general.string = backupCodes.joined(separator: "\n")
                Motion.haptic(.light)
            } label: {
                Text("copy all codes")
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(campusTheme.elevatedSurface)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

            Button {
                AccountPrefsStore.twoFactorBackupCodes = backupCodes
                AccountPrefsStore.twoFactorEnabled = true
                enabled = true
                showEnableSheet = false
                Motion.haptic(.medium)
            } label: {
                Text("i saved them · turn on")
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(campusTheme.background.ignoresSafeArea())
    }
}

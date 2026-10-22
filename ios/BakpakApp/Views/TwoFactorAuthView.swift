import SwiftUI
import UIKit

struct TwoFactorAuthView: View {
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var enabled = AccountPrefsStore.twoFactorEnabled
    @State private var enrollment: PayoutMFA.Enrollment?
    @State private var code = ""
    @State private var isBusy = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var showDisableConfirm = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    CampusPageHeader(title: "two-factor", subtitle: headerSubtitle)

                    if enabled {
                        statusOnCard
                    } else if enrollment != nil {
                        stepIndicator
                        passwordsCard
                        codeCard
                    } else {
                        introCard
                    }

                    primaryButton

                    if !enabled, enrollment != nil {
                        restartButton
                    }

                    if let infoMessage, !infoMessage.isEmpty {
                        Text(infoMessage)
                            .font(Theme.syne(13))
                            .foregroundStyle(campusTheme.textMuted)
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(Theme.syne(13))
                            .foregroundStyle(Color(hex: "#E11D48"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if showDisableConfirm {
                ConfirmActionCard(
                    title: "Turn off two-factor?",
                    message: "You won’t need a Passwords code at sign in, and you won’t be able to cash out until it’s on again.",
                    confirmTitle: "Turn off",
                    confirmIcon: "lock.slash",
                    tone: .destructive,
                    onConfirm: { Task { await turnOff() } },
                    onCancel: { showDisableConfirm = false }
                )
                .zIndex(10)
            }
        }
        .campusPageStyle()
        .task {
            enabled = await PayoutMFA.isEnrolled()
            isLoading = false
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, enrollment != nil, !enabled {
                codeFocused = true
            }
        }
    }

    private var headerSubtitle: String {
        if enabled { return "Passwords authenticator is on" }
        return enrollment == nil ? "protect sign in and cash outs" : "add the key, then verify"
    }

    private var primaryTitle: String {
        if enabled { return "turn off two-factor" }
        if enrollment != nil { return "verify and turn on" }
        return "set up in Passwords"
    }

    private var canSubmit: Bool {
        if enabled { return true }
        if enrollment != nil { return code.count == 6 }
        return !isLoading
    }

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            stepChip(number: 1, title: "Passwords", active: code.isEmpty, done: !code.isEmpty)
            Rectangle()
                .fill(campusTheme.border)
                .frame(height: 1)
            stepChip(number: 2, title: "verify", active: !code.isEmpty, done: false)
        }
    }

    private func stepChip(number: Int, title: String, active: Bool, done: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(active || done ? campusTheme.primary : campusTheme.elevatedSurface)
                    .frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(active ? Color.white : campusTheme.textMuted)
                }
            }
            Text(title)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(active || done ? campusTheme.textPrimary : campusTheme.textMuted)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Passwords app")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("popup opens the Passwords app with your authenticator key. After you add it, enter the 6-digit code here to turn two-factor on. You’ll need that code every time you sign in, and before cash out.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var passwordsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("add popup in Passwords")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Save the popup authenticator in Passwords (or your authenticator app). Come back here and type the 6-digit code it shows.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Motion.haptic(.light)
                Task { await reopenPasswords() }
            } label: {
                Label("open Passwords", systemImage: "arrow.up.forward.app")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

            // Fallback for other authenticator apps, or when Passwords doesn't open.
            if let secret = enrollment?.secret, !secret.isEmpty {
                Button {
                    UIPasteboard.general.string = secret
                    Motion.haptic(.light)
                    infoMessage = "Setup key copied. Paste it into your authenticator app."
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("or copy the setup key")
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                        Text(secret)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy setup key")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("verification code")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Enter the 6-digit code Passwords shows for popup. That turns two-factor on.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            OneTimeCodeField(code: $code, isFocused: $codeFocused) {
                Task { await verifyEnrollment() }
            }
            // Clearing the field after a wrong code must not wipe the error it just set.
            .onChange(of: code) { value in
                if !value.isEmpty { errorMessage = nil }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var restartButton: some View {
        Button {
            Motion.haptic(.light)
            Task { await startEnrollment() }
        } label: {
            Text("set up again")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var statusOnCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(campusTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("on")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("You’ll enter a Passwords code every time you sign in, and before payout changes or cash out.")
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var primaryButton: some View {
        Button {
            Motion.haptic(.medium)
            if enabled {
                showDisableConfirm = true
            } else if enrollment != nil {
                Task { await verifyEnrollment() }
            } else {
                Task { await startEnrollment() }
            }
        } label: {
            Group {
                if isBusy {
                    ProgressView().tint(enabled ? Color(hex: "#E11D48") : .white)
                } else {
                    Text(primaryTitle)
                }
            }
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
        .disabled(isBusy || !canSubmit)
    }

    private func startEnrollment() async {
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            let next = try await PayoutMFA.enroll()
            enrollment = next
            code = ""
            await openAuthenticator(next.uri)
            codeFocused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyEnrollment() async {
        guard let enrollment, code.count == 6, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await PayoutMFA.verify(factorId: enrollment.factorId, code: code)
            let on = await PayoutMFA.isEnrolled()
            guard on else {
                errorMessage = "The code was accepted, but two-factor didn’t finish turning on. Try again."
                return
            }
            self.enrollment = nil
            enabled = true
            code = ""
            infoMessage = nil
            codeFocused = false
            Motion.haptic(.medium)
        } catch {
            errorMessage = Self.verifyErrorMessage(error)
            code = ""
            codeFocused = true
        }
    }

    private func turnOff() async {
        showDisableConfirm = false
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await PayoutMFAGate.shared.requireCode(for: "Confirm it’s you to turn off two-factor.")
            try await PayoutMFA.turnOff()
            enabled = await PayoutMFA.isEnrolled()
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reopenPasswords() async {
        guard let uri = enrollment?.uri else { return }
        await openAuthenticator(uri)
    }

    private func openAuthenticator(_ uri: String) async {
        guard let url = URL(string: uri) else { return }
        let opened = await UIApplication.shared.open(url)
        if !opened {
            infoMessage = "Passwords didn’t open. Copy the setup key above into your authenticator app, then come back."
        }
    }

    private static func verifyErrorMessage(_ error: Error) -> String {
        let lower = error.localizedDescription.lowercased()
        if lower.contains("session") {
            return "Sign in again, then turn on two-factor."
        }
        if lower.contains("expired") || lower.contains("challenge") {
            return "That code expired. Open Passwords and enter the current 6-digit code."
        }
        return "That code didn’t match. Open Passwords and enter the current 6-digit code for popup."
    }
}

/// Six digit boxes over a hidden field; calls `onComplete` when all six are entered.
struct OneTimeCodeField: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding
    var onComplete: () -> Void
    var fill: Color?
    var textColor: Color?
    var border: Color?
    var accent: Color?

    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        let boxFill = fill ?? campusTheme.elevatedSurface
        let boxText = textColor ?? campusTheme.textPrimary
        let boxBorder = border ?? campusTheme.border
        let boxAccent = accent ?? campusTheme.primary

        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused)
                .tint(.clear)
                .foregroundStyle(.clear)
                .accentColor(.clear)
                .frame(height: 64)
                .onChange(of: code) { value in
                    let digits = String(value.filter(\.isNumber).prefix(6))
                    if digits != value { code = digits }
                    if digits.count == 6 { onComplete() }
                }

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let digits = Array(code)
                    let filled = index < digits.count
                    Text(filled ? String(digits[index]) : "")
                        .font(Theme.syne(24, weight: .bold))
                        .foregroundStyle(boxText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(boxFill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    isFocused.wrappedValue && index == min(code.count, 5)
                                        ? boxAccent
                                        : boxBorder,
                                    lineWidth: 1
                                )
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
    }
}

/// Step-up prompt shown by `PayoutMFAGate` before payout changes and cash outs.
struct PayoutCodeSheet: View {
    @ObservedObject var gate: PayoutMFAGate
    @Environment(\.campusTheme) private var campusTheme

    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("enter your code")
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(gate.reason)
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            OneTimeCodeField(code: $code, isFocused: $codeFocused) {
                Task { await verify() }
            }
            // Clearing the field after a wrong code must not wipe the error it just set.
            .onChange(of: code) { value in
                if !value.isEmpty { errorMessage = nil }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.syne(13))
                    .foregroundStyle(Color(hex: "#E11D48"))
            }

            Button {
                Motion.haptic(.medium)
                Task { await verify() }
            } label: {
                Group {
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("continue")
                    }
                }
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(campusTheme.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(isBusy || code.count != 6)

            Button {
                gate.cancelIfPending()
            } label: {
                Text("cancel")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .background(campusTheme.background.ignoresSafeArea())
        .onAppear { codeFocused = true }
    }

    private func verify() async {
        guard code.count == 6, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await PayoutMFA.verifyPayoutCode(code)
            Motion.haptic(.medium)
            gate.verified()
        } catch {
            errorMessage = "That code didn’t match. Try the current one in Passwords."
            code = ""
            codeFocused = true
        }
    }
}

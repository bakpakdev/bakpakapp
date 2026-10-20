import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct TwoFactorAuthView: View {
    @Environment(\.campusTheme) private var campusTheme

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
                    } else if let enrollment {
                        stepIndicator
                        scanCard(enrollment)
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
                    message: "You won’t be able to change payouts or cash out until it’s on again.",
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
    }

    private var headerSubtitle: String {
        if enabled { return "authenticator app is on" }
        return enrollment == nil ? "protect your cash outs" : "scan, then enter the code"
    }

    private var primaryTitle: String {
        if enabled { return "turn off two-factor" }
        if enrollment != nil { return "verify and turn on" }
        return "set up authenticator app"
    }

    private var canSubmit: Bool {
        if enabled { return true }
        if enrollment != nil { return code.count == 6 }
        return !isLoading
    }

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            stepChip(number: 1, title: "scan", active: code.isEmpty, done: !code.isEmpty)
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
            Text("authenticator app")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Use Google Authenticator, 1Password, Authy or the iPhone Passwords app. popup asks for a 6-digit code from it before you change where payouts go or cash out.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private func scanCard(_ enrollment: PayoutMFA.Enrollment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("scan this code")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Open your authenticator app, add an account, and scan. On this phone, tap open in authenticator instead.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let qr = Self.qrImage(enrollment.uri) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("or enter this key")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                Text(Self.grouped(enrollment.secret))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(campusTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(campusTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                smallButton(title: "copy key", icon: "doc.on.doc") {
                    UIPasteboard.general.string = enrollment.secret
                    infoMessage = "Key copied."
                }
                smallButton(title: "open in authenticator", icon: "arrow.up.forward.app") {
                    Task { await openAuthenticator(enrollment.uri) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private func smallButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Motion.haptic(.light)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.syne(12, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(campusTheme.elevatedSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("verification code")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Enter the 6-digit code your authenticator app shows for popup.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            OneTimeCodeField(code: $code, isFocused: $codeFocused) {
                Task { await verifyEnrollment() }
            }
            .onChange(of: code) { _ in errorMessage = nil }
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
            Text("get a new code to scan")
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
                Text("popup asks for a code from your authenticator app before payout changes and cash outs.")
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
            enrollment = try await PayoutMFA.enroll()
            code = ""
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
            self.enrollment = nil
            enabled = true
            code = ""
            infoMessage = nil
            codeFocused = false
            Motion.haptic(.medium)
        } catch {
            errorMessage = "That code didn’t match. Check your authenticator app and try again."
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
            enabled = false
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openAuthenticator(_ uri: String) async {
        guard let url = URL(string: uri) else { return }
        let opened = await UIApplication.shared.open(url)
        if !opened {
            infoMessage = "No authenticator app picked up the link. Copy the key into your app instead."
        }
    }

    private static func grouped(_ secret: String) -> String {
        stride(from: 0, to: secret.count, by: 4).map { start in
            let begin = secret.index(secret.startIndex, offsetBy: start)
            let end = secret.index(begin, offsetBy: 4, limitedBy: secret.endIndex) ?? secret.endIndex
            return String(secret[begin..<end])
        }
        .joined(separator: " ")
    }

    private static func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Six digit boxes over a hidden field; calls `onComplete` when all six are entered.
struct OneTimeCodeField: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding
    var onComplete: () -> Void

    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
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
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    isFocused.wrappedValue && index == min(code.count, 5)
                                        ? campusTheme.primary
                                        : campusTheme.border,
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
            .onChange(of: code) { _ in errorMessage = nil }

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
            errorMessage = "That code didn’t match. Try the current one in your app."
            code = ""
            codeFocused = true
        }
    }
}

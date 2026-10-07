import SwiftUI
import UIKit

struct TwoFactorAuthView: View {
    @Environment(\.campusTheme) private var campusTheme
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var enabled = AccountPrefsStore.twoFactorEnabled
    @State private var phone = AccountPrefsStore.twoFactorPhone
    @State private var code = ""
    @State private var step: Step = AccountPrefsStore.twoFactorEnabled ? .on : .phone
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showDisableConfirm = false
    @State private var resendSeconds = 0
    @State private var previewCode: String?
    @FocusState private var fieldFocus: Field?

    private enum Step {
        case phone
        case code
        case on
    }

    private enum Field: Hashable {
        case phone
        case code
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    CampusPageHeader(title: "two-factor", subtitle: headerSubtitle)

                    if enabled {
                        statusOnCard
                        phoneCard
                    } else {
                        stepIndicator
                        if step == .phone {
                            phoneStep
                        } else {
                            codeStep
                        }
                    }

                    primaryButton

                    if !enabled, step == .code {
                        changeNumberButton
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
                    message: "You won’t be able to cash out until SMS two-factor is on again.",
                    confirmTitle: "Turn off",
                    confirmIcon: "lock.slash",
                    tone: .destructive,
                    onConfirm: { turnOff() },
                    onCancel: { showDisableConfirm = false }
                )
                .zIndex(10)
            }
        }
        .campusPageStyle()
        .onAppear {
            if step == .phone { fieldFocus = .phone }
            if step == .code { fieldFocus = .code }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if resendSeconds > 0 { resendSeconds -= 1 }
        }
    }

    private var headerSubtitle: String {
        if enabled { return "sms codes are on" }
        return step == .code ? "enter the code we texted" : "add your mobile number"
    }

    private var primaryTitle: String {
        if enabled { return "turn off two-factor" }
        if step == .code { return "verify and turn on" }
        return "text me a code"
    }

    private var canSubmit: Bool {
        if enabled { return true }
        if step == .code { return code.filter(\.isNumber).count == 6 }
        return normalizedPhone != nil
    }

    private var normalizedPhone: String? {
        Self.normalize(phone)
    }

    private var maskedPhone: String {
        let digits = (normalizedPhone ?? phone).filter(\.isNumber)
        guard digits.count >= 4 else { return phone.isEmpty ? "your phone" : phone }
        return "••• ••• \(digits.suffix(4))"
    }

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            stepChip(number: 1, title: "number", active: step == .phone, done: step == .code)
            Rectangle()
                .fill(campusTheme.border)
                .frame(height: 1)
            stepChip(number: 2, title: "verify", active: step == .code, done: false)
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

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("mobile number")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("We’ll text a random 6-digit code to this number. Enter that code on the next screen.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("(555) 555-5555", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .focused($fieldFocus, equals: .phone)
                .onChange(of: phone) { value in
                    phone = Self.formatPhone(value)
                    errorMessage = nil
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("verification code")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(previewCode == nil
                 ? "Enter the 6-digit code we just texted to \(maskedPhone)."
                 : "SMS isn’t running on this Mac, so use the preview code below for \(maskedPhone).")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let previewCode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("your code")
                        .font(Theme.syne(12, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                    Text(previewCode)
                        .font(Theme.syne(28, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .kerning(4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($fieldFocus, equals: .code)
                    .tint(.clear)
                    .foregroundStyle(.clear)
                    .accentColor(.clear)
                    .frame(height: 64)
                    .onChange(of: code) { value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        code = digits
                        errorMessage = nil
                        if digits.count == 6 {
                            Task { await verifyCode() }
                        }
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
                                        fieldFocus == .code && index == min(code.count, 5)
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
            .onTapGesture { fieldFocus = .code }

            Button {
                Task { await sendCode(isResend: true) }
            } label: {
                Text(resendSeconds > 0 ? "resend code in \(resendSeconds)s" : "resend code")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(resendSeconds > 0 ? campusTheme.textMuted : campusTheme.primary)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || resendSeconds > 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var changeNumberButton: some View {
        Button {
            Motion.haptic(.light)
            step = .phone
            code = ""
            previewCode = nil
            errorMessage = nil
            fieldFocus = .phone
        } label: {
            Text("use a different number")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
                Text("popup texts a 6-digit code to this phone before cash out.")
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var phoneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("verified number")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(maskedPhone)
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
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
            } else if step == .code {
                Task { await verifyCode() }
            } else {
                Task { await sendCode(isResend: false) }
            }
        } label: {
            Group {
                if isBusy {
                    ProgressView().tint(.white)
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
        .disabled(isBusy || (!enabled && !canSubmit))
    }

    private func sendCode(isResend: Bool) async {
        guard let normalizedPhone else {
            errorMessage = "Enter a valid US mobile number."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await Sms2FAService.send(phone: normalizedPhone)
            phone = Self.formatPhone(response.phone ?? normalizedPhone)
            previewCode = response.previewCode
            step = .code
            if !isResend { code = "" }
            resendSeconds = 30
            fieldFocus = .code
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode() async {
        let trimmed = code.filter(\.isNumber)
        guard trimmed.count == 6 else {
            errorMessage = "Enter the 6-digit code from the text."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await Sms2FAService.verify(code: trimmed)
            AccountPrefsStore.twoFactorEnabled = true
            AccountPrefsStore.twoFactorPhone = response.phone ?? (normalizedPhone ?? phone)
            enabled = true
            step = .on
            code = ""
            previewCode = nil
            fieldFocus = nil
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
            code = ""
            fieldFocus = .code
        }
    }

    private func turnOff() {
        showDisableConfirm = false
        enabled = false
        step = .phone
        code = ""
        phone = ""
        AccountPrefsStore.twoFactorEnabled = false
        AccountPrefsStore.twoFactorPhone = ""
        fieldFocus = .phone
        Motion.haptic(.medium)
    }

    private static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+"), digits.count >= 10 {
            return "+\(digits)"
        }
        return nil
    }

    private static func formatPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        var rest = digits
        if rest.hasPrefix("1"), rest.count > 10 {
            rest = String(rest.dropFirst())
        }
        rest = String(rest.prefix(10))
        if rest.isEmpty { return "" }
        if rest.count <= 3 { return "(\(rest)" }
        let area = rest.prefix(3)
        if rest.count <= 6 {
            return "(\(area)) \(rest.dropFirst(3))"
        }
        let mid = rest.dropFirst(3).prefix(3)
        let last = rest.dropFirst(6)
        return "(\(area)) \(mid)-\(last)"
    }
}

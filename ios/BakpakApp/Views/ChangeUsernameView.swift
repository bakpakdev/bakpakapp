import SwiftUI

/// Dates shown around username changes ("Sat, Dec 6").
enum UsernameDates {
    static func long(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f.string(from: date)
    }

    static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }

    static func month(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date).uppercased()
    }

    static func day(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

    /// When the lock would end if the name changed right now.
    static var unlockIfChangedNow: Date {
        Calendar.current.date(byAdding: .day, value: SupabaseProfileService.usernameLockDays, to: Date()) ?? Date()
    }
}

// MARK: - Shared glass pieces

/// See-through glass used on the username screens, tinted for light and dark.
struct UsernameGlass: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.campusTheme) private var campusTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(campusTheme.isDark ? 0.10 : 0.30),
                                         Color.white.opacity(campusTheme.isDark ? 0.03 : 0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
            )
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(campusTheme.isDark ? 0.16 : 0.55), lineWidth: 1))
    }
}

extension View {
    func usernameGlass(_ cornerRadius: CGFloat = 22) -> some View {
        modifier(UsernameGlass(cornerRadius: cornerRadius))
    }
}

/// Big pill button: solid (white in dark mode, black in light) or glass.
private struct UsernamePillButton: View {
    let title: String
    var solid: Bool = true
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(solid ? campusTheme.background : campusTheme.textPrimary)
                } else {
                    Text(title)
                        .font(Theme.syne(16, weight: .bold))
                        .foregroundStyle(solid ? campusTheme.background : campusTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                if solid {
                    Capsule().fill(campusTheme.textPrimary)
                }
            }
            .modifier(OptionalGlass(enabled: !solid))
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private struct OptionalGlass: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled { content.usernameGlass(27) } else { content }
        }
    }
}

// MARK: - New username screen

/// Its own screen for changing your @, so it feels like a real decision:
/// live availability check, what happens when you switch, an "are you sure"
/// sheet, then a 14-day lock (enforced by the database too).
struct ChangeUsernameView: View {
    let currentUsername: String
    let status: SupabaseProfileService.UsernameChangeStatus
    /// Called after a successful change with the new name and lock status.
    let onChanged: (String, SupabaseProfileService.UsernameChangeStatus) -> Void

    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var check = UsernameAvailabilityChecker()
    @State private var newName = ""
    @State private var showConfirm = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var lockedStatus: SupabaseProfileService.UsernameChangeStatus?
    @FocusState private var fieldFocused: Bool

    private var effectiveStatus: SupabaseProfileService.UsernameChangeStatus { lockedStatus ?? status }
    private var normalized: String { SupabaseProfileService.normalizeUsername(newName) }
    private var hasSpaces: Bool { normalized.contains(where: \.isWhitespace) }
    private var canContinue: Bool {
        !normalized.isEmpty && !hasSpaces && check.status == .available
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(effectiveStatus.locked ? "username" : "new username")
                            .font(Theme.syne(32, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text("currently @\(currentUsername)")
                            .font(Theme.syne(15, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 20)

                    if effectiveStatus.locked {
                        lockedCard
                    } else {
                        field
                        availabilityLine
                        rulesCard
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if !effectiveStatus.locked {
                UsernamePillButton(title: "continue", isEnabled: canContinue) {
                    fieldFocused = false
                    errorText = nil
                    Motion.haptic(.light)
                    showConfirm = true
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .campusPageStyle()
        .sheet(isPresented: $showConfirm) {
            confirmSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(38)
                .presentationBackground(.ultraThinMaterial)
                .interactiveDismissDisabled(isSaving)
        }
        .onAppear { check.currentUsername = currentUsername }
        .task {
            // Focus after the push animation settles, or the keyboard request gets dropped.
            guard !effectiveStatus.locked else { return }
            try? await Task.sleep(nanoseconds: 650_000_000)
            fieldFocused = true
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 2) {
            Text("@")
                .foregroundStyle(campusTheme.textMuted)
            TextField("newname", text: $newName)
                .foregroundStyle(campusTheme.textPrimary)
                .tint(campusTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.username)
                .submitLabel(.continue)
                .focused($fieldFocused)
                .onChange(of: newName) { value in
                    // Typing "@" or spaces doesn't belong in a username.
                    let cleaned = value.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: " ", with: "")
                    if cleaned != value { newName = cleaned; return }
                    check.check(cleaned)
                }
                .onSubmit {
                    if canContinue { showConfirm = true }
                }
        }
        .font(Theme.syne(17, weight: .semibold))
        .padding(.horizontal, 16)
        .frame(height: 54)
        .usernameGlass(18)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    @ViewBuilder
    private var availabilityLine: some View {
        let name = normalized
        Group {
            if name.caseInsensitiveCompare(currentUsername) == .orderedSame, !name.isEmpty {
                label("that's already you", icon: "info.circle.fill", color: campusTheme.textMuted)
            } else {
                switch check.status {
                case .available:
                    label("@\(name) is available", icon: "checkmark.circle.fill", color: Color(hex: "#3DD68C"))
                case .taken:
                    label("@\(name) is taken. Pick a new one.", icon: "exclamationmark.circle.fill", color: Color(hex: "#FF6B6B"))
                case .tooShort:
                    label("at least 3 characters", icon: "exclamationmark.circle.fill", color: campusTheme.textMuted)
                case .checking:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(campusTheme.textMuted)
                        Text("checking…")
                    }
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                case .unknown:
                    label("couldn't check right now. We'll check when you switch.", icon: "wifi.exclamationmark", color: campusTheme.textMuted)
                case .idle:
                    Color.clear.frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .animation(.easeOut(duration: 0.15), value: check.status)
    }

    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(Theme.syne(13, weight: .semibold))
        .foregroundStyle(color)
    }

    private var rulesCard: some View {
        VStack(spacing: 0) {
            ruleRow(1, title: "@\(currentUsername) frees up.", body: "Anyone can grab it once you switch.")
            divider
            ruleRow(2, title: "Old links stop working.", body: "Shared closet links and tags with @\(currentUsername) won't find you.")
            divider
            ruleRow(3, title: "Locked for \(SupabaseProfileService.usernameLockDays) days.", body: "You can't change it again until \(UsernameDates.short(UsernameDates.unlockIfChangedNow)).")
            divider
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Your listings, reviews, chats and followers all stay with you.")
                    .font(Theme.syne(12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(campusTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .usernameGlass(22)
    }

    private var divider: some View {
        Rectangle()
            .fill(campusTheme.textPrimary.opacity(0.09))
            .frame(height: 1)
    }

    private func ruleRow(_ n: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(Theme.syne(12, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(campusTheme.textPrimary.opacity(0.12)))
            (Text(title).font(Theme.syne(13.5, weight: .bold)).foregroundColor(campusTheme.textPrimary)
             + Text(" " + body).font(Theme.syne(13.5, weight: .regular)).foregroundColor(campusTheme.textPrimary.opacity(0.75)))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    // MARK: Locked

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(campusTheme.background)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(campusTheme.textPrimary))
                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(currentUsername) is locked")
                        .font(Theme.syne(17, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    if let until = effectiveStatus.unlocksAt {
                        Text("you can change it again \(UsernameDates.long(until))")
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(campusTheme.textPrimary.opacity(0.12))
                    Capsule().fill(campusTheme.textPrimary)
                        .frame(width: max(8, geo.size.width * effectiveStatus.lockProgress))
                }
            }
            .frame(height: 6)
            Text(lockedExplainer)
                .font(Theme.syne(12.5, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .usernameGlass(24)
    }

    private var lockedExplainer: String {
        var s = "Usernames can change once every \(SupabaseProfileService.usernameLockDays) days so people can always find who they bought from."
        if let changed = effectiveStatus.changedAt {
            s = "You changed it on \(UsernameDates.short(changed)). " + s
        }
        return s
    }

    // MARK: Are you sure

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("switch to @\(normalized)?")
                .font(Theme.syne(24, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("You won't be able to change it again for \(SupabaseProfileService.usernameLockDays) days.")
                .font(Theme.syne(14, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, 6)

            HStack(spacing: 8) {
                Text("@\(currentUsername)")
                    .strikethrough(true, color: campusTheme.textMuted)
                    .foregroundStyle(campusTheme.textMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .usernameGlass(14)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("@\(normalized)")
                    .foregroundStyle(campusTheme.background)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(campusTheme.textPrimary))
            }
            .font(Theme.syne(15, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)

            HStack(spacing: 12) {
                let unlock = UsernameDates.unlockIfChangedNow
                VStack(spacing: 1) {
                    Text(UsernameDates.month(unlock))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(hex: "#E5484D"))
                    Text(UsernameDates.day(unlock))
                        .font(Theme.syne(18, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: 42, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white))
                (Text("Next change unlocks ") + Text(UsernameDates.long(unlock)).bold()
                 + Text(". @\(currentUsername) becomes free for anyone."))
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .usernameGlass(18)
            .padding(.top, 16)

            if let errorText {
                Text(errorText)
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FF6B6B"))
                    .padding(.top, 10)
            }

            Color.clear.frame(height: 20)

            VStack(spacing: 10) {
                UsernamePillButton(title: "yes, switch", isLoading: isSaving) {
                    Task { await commit() }
                }
                UsernamePillButton(title: "keep @\(currentUsername)", solid: false, isEnabled: !isSaving) {
                    showConfirm = false
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func commit() async {
        guard let client = await SupabaseManager.shared.clientWithValidSession() else {
            errorText = "Sign in again to change your username."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await SupabaseProfileService.changeUsername(client: client, to: normalized)
            let finalName = result.username ?? normalized
            Motion.haptic(.heavy)
            showConfirm = false
            onChanged(finalName, result)
            try? await Task.sleep(nanoseconds: 350_000_000)
            dismiss()
        } catch let error as SupabaseProfileService.UsernameChangeError {
            Motion.haptic(.rigid)
            if case .locked(let until) = error {
                lockedStatus = .init(username: currentUsername, changedAt: nil, unlocksAt: until, locked: until != nil)
                showConfirm = false
            } else if case .taken = error {
                check.check(normalized)
            }
            errorText = error.errorDescription
        } catch {
            errorText = SupabaseProfileService.UsernameChangeError.from(error).errorDescription
        }
    }
}

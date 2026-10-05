import SwiftUI

/// In-app confirm card (replaces system confirmation dialogs): dimmed backdrop,
/// campus-styled card, a destructive action and a cancel button.
struct ConfirmActionCard: View {
    let title: String
    let message: String
    let confirmTitle: String
    var confirmIcon: String? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.campusTheme) private var campusTheme
    @State private var appeared = false

    private let destructiveRed = Color(hex: "#E11D48")

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.42 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss(then: onCancel) }

            VStack(spacing: 20) {
                Image(systemName: confirmIcon ?? "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(destructiveRed)
                    .frame(width: 56, height: 56)
                    .background(destructiveRed.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 6) {
                    Text(title)
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(Theme.syne(14))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button {
                        Motion.haptic(.medium)
                        dismiss(then: onConfirm)
                    } label: {
                        Text(confirmTitle)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(destructiveRed)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

                    Button {
                        Motion.haptic(.light)
                        dismiss(then: onCancel)
                    } label: {
                        Text("Cancel")
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
            .padding(.horizontal, 28)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(Motion.bounce) { appeared = true }
        }
    }

    private func dismiss(then action: @escaping () -> Void) {
        withAnimation(Motion.snappy) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { action() }
    }
}

struct SettingsSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var showDivider: Bool = true
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.syne(12))
                            .foregroundStyle(campusTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                EditProfileIOSSwitch(isOn: $isOn)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct SettingsNavRow: View {
    var icon: String? = nil
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    let action: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(Theme.syne(12))
                                .foregroundStyle(campusTheme.textMuted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDivider {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
                    .padding(.leading, icon == nil ? 16 : 70)
            }
        }
    }
}

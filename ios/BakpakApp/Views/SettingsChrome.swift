import SwiftUI

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

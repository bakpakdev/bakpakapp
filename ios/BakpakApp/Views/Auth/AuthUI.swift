import SwiftUI

// MARK: - Soft glow background (same treatment as CampusPageBackground, PopupBrand colors)

struct AuthPageBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            PopupBrand.background.ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: -150, y: -110)

            Circle()
                .fill(Color.white.opacity(0.045))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: 175, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - Shared auth field / button

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PopupBrand.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PopupBrand.border, lineWidth: 1)
            )
            .foregroundStyle(PopupBrand.textPrimary)
            .tint(PopupBrand.textPrimary)
    }
}

extension View {
    func authFieldStyle() -> some View {
        modifier(AuthFieldStyle())
    }
}

struct AuthPrimaryButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: {
            Motion.haptic(.medium)
            action()
        }) {
            HStack {
                label
                    .font(Theme.syne(16, weight: .semibold))
            }
            .foregroundStyle(PopupBrand.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PopupBrand.button)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }
}

struct AuthScreenChrome<Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuthPageBackground()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        Motion.haptic(.light)
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PopupBrand.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(PopupBrand.field)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(PopupBrand.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))

                    Text("popup")
                        .font(Theme.syne(28, weight: .black))
                        .tracking(-0.5)
                        .foregroundStyle(PopupBrand.textPrimary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                content
            }
        }
    }
}

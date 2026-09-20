import SwiftUI

// MARK: - Shared auth field / button

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(PopupBrand.field)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PopupBrand.border, lineWidth: 1)
            )
            .foregroundStyle(PopupBrand.textPrimary)
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
            .background(PopupBrand.button)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }
}

struct AuthScreenChrome<Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            PopupBrand.background.ignoresSafeArea()

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
                            .background(PopupBrand.field)
                            .clipShape(Circle())
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

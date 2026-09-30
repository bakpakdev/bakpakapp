import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        ZStack {
            PopupBrand.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("popup")
                    .font(Theme.syne(34, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(PopupBrand.textPrimary)

                Text("What's Poppin' on YOUR Campus")
                    .font(Theme.syne(14, weight: .medium))
                    .italic()
                    .foregroundStyle(PopupBrand.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Motion.haptic(.medium)
                        onGetStarted()
                    } label: {
                        Text("Get Started")
                            .font(Theme.syne(16, weight: .semibold))
                            .foregroundStyle(PopupBrand.buttonText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(PopupBrand.button)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                    Button {
                        Motion.haptic(.light)
                        onSignIn()
                    } label: {
                        Text("I already have an account")
                            .font(Theme.syne(15, weight: .medium))
                            .foregroundStyle(PopupBrand.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    WelcomeView(onGetStarted: {}, onSignIn: {})
}

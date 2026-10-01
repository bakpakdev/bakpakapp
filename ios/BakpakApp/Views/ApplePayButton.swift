import SwiftUI

/// Official-looking black Apple Pay control. Use `receiving: true` for Tap to Pay receive.
struct ApplePayButton: View {
    var title: String
    var receiving: Bool = false
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "applelogo")
                        .font(.system(size: 18, weight: .semibold))
                    Text(title)
                        .font(Theme.syne(17, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.black)
            .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
        .accessibilityLabel(receiving ? "Receive with Apple Pay" : title)
    }
}

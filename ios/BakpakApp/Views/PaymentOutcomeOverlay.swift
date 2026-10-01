import SwiftUI

enum PaymentOutcomeKind {
    case success
    case failure
}

/// Full-screen Apple Pay result: three dots spin, swirl inward, then become a checkmark or a red X.
struct PaymentOutcomeOverlay: View {
    let kind: PaymentOutcomeKind
    var isCollecting: Bool = false
    /// When set, the animation is frozen at this elapsed time (screenshots / previews).
    var freezeElapsed: TimeInterval? = nil
    var onContinue: () -> Void

    @Environment(\.campusTheme) private var campusTheme
    @State private var startedAt = Date()
    @State private var didHaptic = false

    private let failRed = Color(hex: "#E11D48")
    private let spinEnd: TimeInterval = 1.15
    private let swirlEnd: TimeInterval = 1.65

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = freezeElapsed ?? context.date.timeIntervalSince(startedAt)
            content(elapsed: elapsed)
                .onChange(of: elapsed) { value in
                    fireHapticIfNeeded(elapsed: value)
                }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind == .success ? "Purchase was successful" : "Purchase was unsuccessful")
    }

    private func content(elapsed: TimeInterval) -> some View {
        let spinning = elapsed < swirlEnd
        let resultAmount = clamp((elapsed - swirlEnd) / 0.18)
        let copyAmount = clamp((elapsed - 1.9) / 0.28)
        let buttonAmount = clamp((elapsed - 2.2) / 0.22)

        return ZStack {
            CampusPageBackground()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    orbitingDots(elapsed: elapsed)
                        .opacity(spinning ? 1 : max(0, 1 - resultAmount * 2))

                    resultBadge
                        .scaleEffect(0.2 + 0.8 * resultAmount)
                        .opacity(resultAmount)
                }
                .frame(width: 160, height: 160)

                VStack(spacing: 8) {
                    Text(kind == .success ? "purchase was successful" : "purchase was unsuccessful")
                        .font(Theme.syne(28, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)

                    Text(subtitle)
                        .font(Theme.syne(16, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .opacity(copyAmount)

                Spacer()

                Button(action: onContinue) {
                    Text(kind == .success ? "continue" : "try again")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(kind == .success ? campusTheme.primary : failRed)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .opacity(buttonAmount)
                .disabled(buttonAmount < 0.8)
            }
        }
    }

    private var subtitle: String {
        switch kind {
        case .success:
            return isCollecting
                ? "apple pay went through · the buyer paid you"
                : "apple pay went through · the seller got paid"
        case .failure:
            return "apple pay didn’t go through · you can try again"
        }
    }

    private func orbitingDots(elapsed: TimeInterval) -> some View {
        let radius: CGFloat = {
            if elapsed <= spinEnd { return 46 }
            let t = min(1, (elapsed - spinEnd) / (swirlEnd - spinEnd))
            let eased = t * t
            return 46 * (1 - eased)
        }()
        let angle: Double = {
            if elapsed <= spinEnd {
                return elapsed / 0.62 * 360
            }
            let extra = (elapsed - spinEnd) / 0.5 * 280
            return spinEnd / 0.62 * 360 + extra
        }()

        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(campusTheme.primary)
                    .frame(width: 22, height: 22)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle + Double(index) * 120))
            }
        }
    }

    private var resultBadge: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(kind == .success ? campusTheme.primary : failRed)
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: kind == .success ? "checkmark" : "xmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(
                color: (kind == .success ? campusTheme.primary : failRed).opacity(0.28),
                radius: 18,
                y: 8
            )
    }

    private func fireHapticIfNeeded(elapsed: TimeInterval) {
        guard freezeElapsed == nil, !didHaptic, elapsed >= swirlEnd else { return }
        didHaptic = true
        Motion.haptic(kind == .success ? .medium : .heavy)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

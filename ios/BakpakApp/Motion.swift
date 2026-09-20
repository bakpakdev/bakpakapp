import SwiftUI
import UIKit

// MARK: - Spring presets

enum Motion {
    /// Playful bounce for sheets, tabs, and large moves.
    static let bounce = Animation.spring(response: 0.48, dampingFraction: 0.68, blendDuration: 0.12)

    /// Quick tap feedback on buttons and chips.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.72, blendDuration: 0.08)

    /// Soft settle for subtle UI changes.
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0.1)

    /// Follows finger while dragging.
    static let interactive = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.15)

    static func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        if offset <= limit { return offset }
        let overshoot = offset - limit
        return limit + overshoot * 0.28
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Button styles

struct BouncyButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct BouncyCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - View modifiers

struct TabBounceModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    let tab: AppTab

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.selectedTab) { newTab in
                guard newTab == tab else { return }
                Motion.haptic(.light)
            }
    }
}

struct PressableCardModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        Button {
            Motion.haptic(.soft)
            action()
        } label: {
            content
        }
        .buttonStyle(BouncyCardButtonStyle())
    }
}

extension View {
    func tabBounce(_ tab: AppTab) -> some View {
        modifier(TabBounceModifier(tab: tab))
    }

    func pressableCard(action: @escaping () -> Void) -> some View {
        modifier(PressableCardModifier(action: action))
    }

    func popupBounceAnimation<V: Equatable>(value: V) -> some View {
        animation(Motion.bounce, value: value)
    }
}

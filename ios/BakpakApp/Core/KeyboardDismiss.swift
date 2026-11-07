import SwiftUI
import UIKit

/// Tapping anywhere outside a text field closes the keyboard, app-wide.
/// The tap still reaches whatever was under it, and taps on another field
/// are ignored so moving between fields doesn't bounce the keyboard.
final class KeyboardDismiss: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismiss()

    func install() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey(_:)),
            name: UIWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowBecameKey(_ note: Notification) {
        guard let window = note.object as? UIWindow,
              !(window.gestureRecognizers ?? []).contains(where: { $0.name == Self.recognizerName }) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.name = Self.recognizerName
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        tap.view?.endEditing(true)
    }

    /// Window-space areas (e.g. a chat's input bar) where a tap keeps the keyboard up,
    /// so tapping send leaves the keyboard open like Messages does.
    private var keepOpenFrames: [UUID: CGRect] = [:]

    func setKeepOpenFrame(_ frame: CGRect?, for id: UUID) {
        keepOpenFrames[id] = frame
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: nil)
        if keepOpenFrames.values.contains(where: { $0.contains(point) }) { return false }
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView || v is UISearchBar { return false }
            view = v.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private static let recognizerName = "popup.keyboardDismiss"
}

private struct KeepsKeyboardOpen: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    Color.clear
                        .onAppear { KeyboardDismiss.shared.setKeepOpenFrame(frame, for: id) }
                        .onChange(of: frame) { KeyboardDismiss.shared.setKeepOpenFrame($0, for: id) }
                }
            )
            .onDisappear { KeyboardDismiss.shared.setKeepOpenFrame(nil, for: id) }
    }
}

extension View {
    /// Taps inside this view don't close the keyboard (the app closes it on any other tap).
    func keepsKeyboardOpen() -> some View {
        modifier(KeepsKeyboardOpen())
    }
}

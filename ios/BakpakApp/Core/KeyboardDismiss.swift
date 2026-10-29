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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
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

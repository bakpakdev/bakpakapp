import Foundation
import SwiftUI
import UIKit

/// Campus prices and offers: 0.00 ... 999.99.
/// Typing is cashier-style: digits fill cents first, then shift into dollars.
enum MoneyAmount {
    static let maximum: Double = 999.99
    private static let maxCents = 99_999

    static func centsBinding(_ text: Binding<String>, floorAtZero: Bool = false) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = applyCentsFirst(previous: text.wrappedValue, incoming: $0, floorAtZero: floorAtZero) }
        )
    }

    static func applyCentsFirst(previous: String, incoming: String, floorAtZero: Bool = false) -> String {
        let prev = previous.filter(\.isNumber)
        let next = incoming.filter(\.isNumber)
        if next.isEmpty {
            if floorAtZero && !prev.isEmpty { return display(0) }
            return ""
        }

        var cents = Int(prev) ?? 0
        if next.count > prev.count {
            for ch in next.suffix(next.count - prev.count) {
                guard let digit = ch.wholeNumberValue else { continue }
                let grown = cents * 10 + digit
                if grown > maxCents { return display(cents) }
                cents = grown
            }
        } else if next.count < prev.count, isBackspace(prev: prev, next: next) {
            for _ in 0..<(prev.count - next.count) {
                cents /= 10
            }
        } else {
            cents = min(Int(next) ?? 0, maxCents)
        }
        return display(cents)
    }

    static func sanitized(_ raw: String) -> String {
        applyCentsFirst(previous: "", incoming: raw.filter(\.isNumber))
    }

    static func formatted(_ value: Double) -> String {
        let clamped = min(max(value, 0), maximum)
        return display(Int((clamped * 100).rounded()))
    }

    static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        if value < 0 { return 0 }
        return min(value, maximum)
    }

    fileprivate static func display(_ cents: Int) -> String {
        let value = min(max(cents, 0), maxCents)
        return String(format: "%d.%02d", value / 100, value % 100)
    }

    private static func isBackspace(prev: String, next: String) -> Bool {
        prev.hasPrefix(next) || String(prev.dropLast(max(0, prev.count - next.count))) == next
    }
}

/// Number pad that never shows digits past $999.99 and never deletes below $0.00.
struct MoneyCentsField: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var textColor: Color
    var floorAtZero: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.adjustsFontForContentSizeCategory = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let base = UIFont(name: "Syne", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .bold)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            field.font = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            field.font = base
        }
        field.textColor = UIColor(textColor)
        if field.text != text {
            field.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MoneyCentsField
        init(_ parent: MoneyCentsField) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let incoming = current.replacingCharacters(in: swiftRange, with: string)
            let applied = MoneyAmount.applyCentsFirst(
                previous: current,
                incoming: incoming,
                floorAtZero: parent.floorAtZero
            )
            if applied == current { return false }
            textField.text = applied
            parent.text = applied
            return false
        }
    }
}

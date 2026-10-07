import Foundation

/// Campus prices and offers: at most 3 integer digits and 2 decimal places (0.00 ... 999.99).
enum MoneyAmount {
    static let maximum: Double = 999.99

    static func sanitized(_ raw: String) -> String {
        let filtered = raw.filter { $0.isNumber || $0 == "." }
        var integer = ""
        var fraction = ""
        var seenDot = false
        for ch in filtered {
            if ch == "." {
                if seenDot { continue }
                seenDot = true
                continue
            }
            if seenDot {
                if fraction.count < 2 { fraction.append(ch) }
            } else if integer.count < 3 {
                integer.append(ch)
            }
        }
        if integer.isEmpty && (seenDot || !fraction.isEmpty) { integer = "0" }
        if integer.count > 1 { integer = String(integer.drop { $0 == "0" && integer.count > 1 }) }
        if seenDot { return "\(integer).\(fraction)" }
        return integer
    }

    static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        if value < 0 { return 0 }
        return min(value, maximum)
    }
}

import Foundation

/// An entry fee as organizers and Claude actually write it: `$27`,
/// `EUR 18 per single image`, `€18-21`, `27 USD`, `HUF 5,000`, `Free`.
public enum EntryFee {
    public struct Amount: Equatable {
        public var currency: String
        public var value: Double
    }

    private static let symbols: [String: String] = [
        "US$": "USD", "$": "USD", "€": "EUR", "£": "GBP", "Ft": "HUF",
    ]

    private static let codePattern = try! NSRegularExpression(pattern: "\\b([A-Z]{3})\\b")
    private static let numberPattern = try! NSRegularExpression(pattern: "\\d+(?:[.,]\\d+)*")

    /// Nil for a free entry, or for text with no amount in it. A range such
    /// as `€18-21` counts its first figure: the fee actually paid is at least
    /// that, and guessing higher would overstate what was spent.
    public static func parse(_ text: String) -> Amount? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "free" else { return nil }
        let whole = NSRange(trimmed.startIndex..., in: trimmed)

        guard let numberMatch = numberPattern.firstMatch(in: trimmed, range: whole),
              let numberRange = Range(numberMatch.range, in: trimmed),
              let value = number(String(trimmed[numberRange])) else { return nil }

        var currency: String?
        if let codeMatch = codePattern.firstMatch(in: trimmed, range: whole),
           let range = Range(codeMatch.range(at: 1), in: trimmed) {
            currency = String(trimmed[range])
        } else {
            // Longest symbol first, so US$ is not read as a bare $.
            for symbol in symbols.keys.sorted(by: { $0.count > $1.count }) where trimmed.contains(symbol) {
                currency = symbols[symbol]
                break
            }
        }
        guard let currency else { return nil }
        return Amount(currency: currency, value: value)
    }

    /// `5,000` and `5.000` are thousands; `27.50` and `27,50` are decimals.
    private static func number(_ text: String) -> Double? {
        let separators = text.filter { $0 == "," || $0 == "." }
        if let last = text.lastIndex(where: { $0 == "," || $0 == "." }) {
            let decimals = text.distance(from: text.index(after: last), to: text.endIndex)
            if decimals == 3 || separators.count > 1 {
                return Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: ""))
            }
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return Double(text)
    }
}

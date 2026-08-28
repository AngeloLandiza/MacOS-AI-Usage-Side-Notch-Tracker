import Foundation

/// Pure formatting helpers, injectable `now`/timezone so they are testable.
enum Fmt {
    /// "73%" — whole-number percent from a 0...1 fraction.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction.unitClamped * 100).rounded()))%"
    }

    /// "$12.40" (two decimals), "$1,204" (no decimals once ≥ $100).
    static func money(_ amount: Double, currency: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = abs(amount) >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// "Resets in 51 min" / "Resets in 3 hr 20 min" for near resets,
    /// "Resets Thu 12:00 AM" for anything a day or more away.
    static func reset(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resets soon" }
        if interval < 24 * 3600 {
            let minutes = Int(interval / 60)   // floor: "51 min" until it flips to 50
            if minutes < 1 { return "Resets in <1 min" }
            if minutes < 60 { return "Resets in \(minutes) min" }
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "Resets in \(h) hr" : "Resets in \(h) hr \(m) min"
        }
        let df = DateFormatter()
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE h:mm a"
        return "Resets \(df.string(from: date))"
    }
}

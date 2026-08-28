import SwiftUI

/// Identity and looks of a provider, independent of any fetched data.
struct ProviderInfo: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let glyph: Glyph

    enum Glyph: Sendable, Equatable {
        case claude, openAI, gemini, openRouter, deepSeek
        case monogram(String)
    }
}

/// One row in the hover card ("Current session — Resets in 51 min — 73% Used").
struct Metric: Sendable, Equatable {
    var label: String
    var sublabel: String?
    var fraction: Double?
    var footnote: String?
}

/// Everything the UI needs to render one provider's current state.
struct ProviderStatus: Sendable, Equatable {
    /// 0...1 usage for the ring. `nil` for balance-only providers (full ring).
    var ringFraction: Double?
    /// Text under the ring: "73%" or "$12.40".
    var ringLabel: String
    var metrics: [Metric] = []
    /// "Balance: $12.40" shown in the card when the provider exposes credits.
    var credits: String?
}

enum LoadState: Sendable, Equatable {
    case loading
    case ok(ProviderStatus)
    case failed(String)
}

extension Double {
    /// Clamps to 0...1 for ring drawing.
    var unitClamped: Double { min(max(self, 0), 1) }
}

/// Ring/bar color by utilization, matching the mock: green → yellow → red-orange.
func usageColor(fraction: Double?) -> Color {
    guard let f = fraction else { return .green }
    switch f {
    case ..<0.35: return Color(red: 0.20, green: 0.85, blue: 0.45)
    case ..<0.70: return Color(red: 0.95, green: 0.85, blue: 0.15)
    default: return Color(red: 1.00, green: 0.28, blue: 0.10)
    }
}

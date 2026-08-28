import SwiftUI

/// Base layout constants; anything the size slider affects goes through
/// `NotchMetrics` so the whole notch scales together.
enum Theme {
    static let itemHeight: CGFloat = 92
    static let ringSize: CGFloat = 50
    static let ringLineWidth: CGFloat = 5
    static let notchBodyWidth: CGFloat = 92
    static let notchFlare: CGFloat = 26
    static let cardWidth: CGFloat = 300
    static let cardGap: CGFloat = 8
    /// Margin around the card inside its panel so the drop shadow isn't clipped.
    static let cardShadowPad: CGFloat = 22
    static let maxVisibleItems = 3
    /// Width of the strip left visible when auto-hide tucks the notch away.
    static let autoHideSliver: CGFloat = 10

    static let notchBackground = Color.black
    static let cardBackground = Color.black
    static let trackColor = Color.white.opacity(0.18)
}

/// Scaled dimensions for the notch panel and its contents.
struct NotchMetrics: Equatable {
    var scale: CGFloat = 1

    var itemHeight: CGFloat { Theme.itemHeight * scale }
    var ringSize: CGFloat { Theme.ringSize * scale }
    var ringLineWidth: CGFloat { Theme.ringLineWidth * scale }
    var bodyWidth: CGFloat { Theme.notchBodyWidth * scale }
    var flare: CGFloat { Theme.notchFlare * scale }
    var labelSize: CGFloat { 14 * scale }

    func notchHeight(itemCount: Int) -> CGFloat {
        let visible = min(Theme.maxVisibleItems, max(1, itemCount))
        return CGFloat(visible) * itemHeight + 2 * flare
    }
}

import SwiftUI

/// Layout constants shared by the notch and the hover card.
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

    static let notchBackground = Color.black
    static let cardBackground = Color.black
    static let trackColor = Color.white.opacity(0.18)

    static func notchHeight(itemCount: Int) -> CGFloat {
        let visible = min(maxVisibleItems, max(1, itemCount))
        return CGFloat(visible) * itemHeight + 2 * notchFlare
    }
}

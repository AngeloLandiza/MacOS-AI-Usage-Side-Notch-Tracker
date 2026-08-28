import SwiftUI

/// The side-notch silhouette: flush with the screen's right edge, with S-curve
/// flares at top and bottom that blend into the edge (like a hardware notch
/// rotated onto the side of the display).
struct NotchShape: Shape {
    var flare: CGFloat = Theme.notchFlare

    func path(in rect: CGRect) -> Path {
        let w = rect.maxX
        let h = rect.maxY
        let left = rect.maxX - Theme.notchBodyWidth
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        // Top flare: leaves the screen edge vertically, lands on the body's
        // left side vertically — a smooth S.
        p.addCurve(
            to: CGPoint(x: left, y: flare),
            control1: CGPoint(x: w, y: flare),
            control2: CGPoint(x: left, y: 0)
        )
        p.addLine(to: CGPoint(x: left, y: h - flare))
        // Bottom flare, mirrored.
        p.addCurve(
            to: CGPoint(x: w, y: h),
            control1: CGPoint(x: left, y: h),
            control2: CGPoint(x: w, y: h - flare)
        )
        p.closeSubpath()
        return p
    }
}

import SwiftUI

/// Circular usage gauge with the provider glyph in the middle.
struct RingGauge: View {
    let glyph: ProviderInfo.Glyph
    let fraction: Double?   // nil → balance-only, draw a full ring
    var dimmed = false
    var metrics = NotchMetrics()

    var body: some View {
        let shown = (fraction ?? 1).unitClamped
        ZStack {
            Circle()
                .stroke(Theme.trackColor, lineWidth: metrics.ringLineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    usageColor(fraction: fraction),
                    style: StrokeStyle(lineWidth: metrics.ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: shown)
            ProviderGlyph(glyph: glyph, size: metrics.ringSize * 0.42)
        }
        .frame(width: metrics.ringSize, height: metrics.ringSize)
        .opacity(dimmed ? 0.35 : 1)
    }
}

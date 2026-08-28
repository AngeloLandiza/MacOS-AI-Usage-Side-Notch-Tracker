import SwiftUI

/// Hover card shown to the left of the notch: metric rows with bars, reset
/// times, and credits — mirroring the mock's "Claude Usage" bubble.
struct DetailCard: View {
    let info: ProviderInfo
    let state: LoadState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProviderGlyph(glyph: info.glyph, size: 16)
                    Text("\(info.name) Usage")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                switch state {
                case .loading:
                    Text("Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                case let .failed(message):
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(3)
                case let .ok(status):
                    ForEach(Array(status.metrics.enumerated()), id: \.offset) { _, metric in
                        MetricRow(metric: metric)
                    }
                    if let credits = status.credits {
                        HStack {
                            Text("Credits")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(credits)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: Theme.cardWidth, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            CardPointer()
                .fill(Theme.cardBackground)
                .frame(width: 12, height: 22)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

private struct MetricRow: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(metric.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if let sublabel = metric.sublabel {
                    Text(sublabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            if let fraction = metric.fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.trackColor)
                        Capsule()
                            .fill(usageColor(fraction: fraction))
                            .frame(width: max(6, geo.size.width * fraction.unitClamped))
                    }
                }
                .frame(height: 6)
            }
            if let footnote = metric.footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}

/// Small triangle pointing at the hovered ring.
private struct CardPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

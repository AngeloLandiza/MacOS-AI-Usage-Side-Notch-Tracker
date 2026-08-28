import SwiftUI

/// Which provider the pointer is over, and where its cell sits vertically
/// (window-content coordinates) so the card can align with it.
struct Hover: Equatable {
    let providerID: String
    let midY: CGFloat
}

@MainActor
final class HoverModel: ObservableObject {
    @Published var hover: Hover?
}

/// The notch itself: black flared shape containing a snap-scrolling column of
/// ring gauges, up to three visible at a time.
struct NotchView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var hoverModel: HoverModel
    @ObservedObject var settings: AppSettings
    var onNotchHover: (Bool) -> Void
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        let metrics = NotchMetrics(scale: settings.scale)
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if store.providers.isEmpty {
                    EmptyCell(metrics: metrics, onSettings: onSettings)
                } else {
                    ForEach(store.providers) { info in
                        ProviderCell(
                            info: info,
                            state: store.states[info.id] ?? .loading,
                            metrics: metrics,
                            hoverModel: hoverModel
                        )
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.never)
        .frame(width: metrics.bodyWidth)
        .padding(.vertical, metrics.flare)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            NotchShape(bodyWidth: metrics.bodyWidth, flare: metrics.flare)
                .fill(Theme.notchBackground)
        )
        .onHover(perform: onNotchHover)
        .contextMenu {
            Button("Refresh", action: onRefresh)
            Button("Settings…", action: onSettings)
            Divider()
            Button("Quit AI Side Notch", action: onQuit)
        }
    }
}

private struct ProviderCell: View {
    let info: ProviderInfo
    let state: LoadState
    let metrics: NotchMetrics
    @ObservedObject var hoverModel: HoverModel

    var body: some View {
        VStack(spacing: 7 * metrics.scale) {
            RingGauge(glyph: info.glyph, fraction: ringFraction, dimmed: isFailed, metrics: metrics)
            Text(ringLabel)
                .font(.system(size: metrics.labelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: metrics.bodyWidth, height: metrics.itemHeight)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CellFrameKey.self,
                    value: [info.id: geo.frame(in: .global).midY]
                )
            }
        )
        .onPreferenceChange(CellFrameKey.self) { frames in
            let midY = frames[info.id]
            Task { @MainActor in
                cellMidY = midY ?? cellMidY
                // Keep the card tracking the cell while the column scrolls.
                if hoverModel.hover?.providerID == info.id, let midY {
                    hoverModel.hover = Hover(providerID: info.id, midY: midY)
                }
            }
        }
        .onHover { inside in
            if inside {
                hoverModel.hover = Hover(providerID: info.id, midY: cellMidY)
            } else if hoverModel.hover?.providerID == info.id {
                hoverModel.hover = nil
            }
        }
    }

    @State private var cellMidY: CGFloat = 0

    private var ringFraction: Double? {
        if case let .ok(status) = state { return status.ringFraction }
        return 0
    }

    private var ringLabel: String {
        switch state {
        case .loading: "…"
        case .failed: "!"
        case let .ok(status): status.ringLabel
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}

private struct EmptyCell: View {
    let metrics: NotchMetrics
    var onSettings: () -> Void

    var body: some View {
        Button(action: onSettings) {
            VStack(spacing: 7) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22 * metrics.scale))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Set up")
                    .font(.system(size: 12 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .frame(width: metrics.bodyWidth, height: metrics.itemHeight)
    }
}

private struct CellFrameKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

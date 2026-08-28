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
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if store.providers.isEmpty {
                    EmptyCell(onSettings: onSettings)
                } else {
                    ForEach(store.providers) { info in
                        ProviderCell(
                            info: info,
                            state: store.states[info.id] ?? .loading,
                            hoverModel: hoverModel
                        )
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(width: Theme.notchBodyWidth)
        .padding(.vertical, Theme.notchFlare)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(NotchShape().fill(Theme.notchBackground))
        .contextMenu {
            Button("Refresh", action: onRefresh)
            Button("Settings…", action: onSettings)
            Divider()
            Button("Quit Side Notch", action: onQuit)
        }
    }
}

private struct ProviderCell: View {
    let info: ProviderInfo
    let state: LoadState
    @ObservedObject var hoverModel: HoverModel

    var body: some View {
        VStack(spacing: 7) {
            RingGauge(glyph: info.glyph, fraction: ringFraction, dimmed: isFailed)
            Text(ringLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: Theme.notchBodyWidth, height: Theme.itemHeight)
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
    var onSettings: () -> Void

    var body: some View {
        Button(action: onSettings) {
            VStack(spacing: 7) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Set up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .frame(width: Theme.notchBodyWidth, height: Theme.itemHeight)
    }
}

private struct CellFrameKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

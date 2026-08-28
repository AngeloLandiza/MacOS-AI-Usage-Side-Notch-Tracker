import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let hoverModel = HoverModel()
    private var notchPanel: NSPanel!
    private var cardPanel: NSPanel!
    private var cardHost: NSHostingView<CardHost>!
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var hideCardTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeNotchPanel()
        makeCardPanel()
        store.start()

        store.$providers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] providers in self?.layoutNotch(itemCount: providers.count) }
            .store(in: &subscriptions)
        hoverModel.$hover
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hover in self?.hoverChanged(hover) }
            .store(in: &subscriptions)
        store.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.cardPanel.isVisible == true { self?.positionCard() }
            }
            .store(in: &subscriptions)
    }

    // MARK: - Panels

    private func makeNotchPanel() {
        let root = NotchView(
            store: store,
            hoverModel: hoverModel,
            onRefresh: { [weak self] in Task { await self?.store.refreshAll(force: true) } },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: root)
        notchPanel = panel
        layoutNotch(itemCount: 0)
        panel.orderFrontRegardless()
    }

    private func makeCardPanel() {
        cardHost = NSHostingView(rootView: CardHost(store: store, hoverModel: hoverModel))
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true   // display-only, never swallows clicks
        panel.contentView = cardHost
        panel.alphaValue = 0
        cardPanel = panel
    }

    private var screen: NSScreen? { NSScreen.screens.first }

    private func layoutNotch(itemCount: Int) {
        guard let screen else { return }
        let size = NSSize(width: Theme.notchBodyWidth, height: Theme.notchHeight(itemCount: itemCount))
        let origin = NSPoint(
            x: screen.frame.maxX - size.width,
            y: screen.visibleFrame.maxY - size.height - 8
        )
        notchPanel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Hover card

    private func hoverChanged(_ hover: Hover?) {
        hideCardTask?.cancel()
        if hover != nil {
            positionCard()
            cardPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                cardPanel.animator().alphaValue = 1
            }
        } else {
            // Small grace period so sliding between cells doesn't flicker.
            hideCardTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    self.cardPanel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor in
                        if self?.hoverModel.hover == nil { self?.cardPanel.orderOut(nil) }
                    }
                })
            }
        }
    }

    private func positionCard() {
        guard let hover = hoverModel.hover else { return }
        let size = cardHost.fittingSize
        // SwiftUI `.global` y is top-down within the window; convert to screen.
        let anchorY = notchPanel.frame.maxY - hover.midY
        let origin = NSPoint(
            x: notchPanel.frame.minX - size.width - Theme.cardGap,
            y: anchorY - size.height / 2
        )
        cardPanel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Settings

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Side Notch Settings"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Card content bound to the hovered provider; lives in its own panel.
struct CardHost: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var hoverModel: HoverModel

    var body: some View {
        if let hover = hoverModel.hover,
           let info = store.providers.first(where: { $0.id == hover.providerID }) {
            DetailCard(info: info, state: store.states[info.id] ?? .loading)
                .padding(6)
        }
    }
}

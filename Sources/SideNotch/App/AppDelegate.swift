import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = UsageStore()
    private let settings = AppSettings()
    private let hoverModel = HoverModel()
    private var notchPanel: NSPanel!
    private var cardPanel: NSPanel!
    private var cardHost: NSHostingView<CardHost>!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var hideCardTask: Task<Void, Never>?
    private var tuckNotchTask: Task<Void, Never>?
    /// While auto-hide is on, whether the notch is currently slid out.
    private var notchRevealed = true
    /// Whether the pointer is anywhere over the notch (cells or flares).
    private var pointerInsideNotch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeNotchPanel()
        makeCardPanel()
        makeStatusItem()
        store.start()

        store.$providers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layoutNotch() }
            .store(in: &subscriptions)
        settings.$scale
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layoutNotch() }
            .store(in: &subscriptions)
        settings.$autoHide
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.tuckNotchTask?.cancel()
                self.notchRevealed = true
                self.applyNotchFrame(animated: true)
                if enabled { self.scheduleTuck() }
            }
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
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layoutNotch() }
            .store(in: &subscriptions)
    }

    private var metrics: NotchMetrics { NotchMetrics(scale: settings.scale) }

    // MARK: - Panels

    private func makeNotchPanel() {
        let root = NotchView(
            store: store,
            hoverModel: hoverModel,
            settings: settings,
            onNotchHover: { [weak self] inside in self?.notchHoverChanged(inside: inside) },
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
        layoutNotch()
        panel.orderFrontRegardless()
        if settings.autoHide { scheduleTuck() }
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

    private func layoutNotch() {
        applyNotchFrame(animated: false)
    }

    /// Positions the notch flush to the right edge — or tucked away to a thin
    /// sliver when auto-hide has it hidden.
    private func applyNotchFrame(animated: Bool) {
        guard let screen, notchPanel != nil else { return }
        let m = metrics
        let size = NSSize(width: m.bodyWidth, height: m.notchHeight(itemCount: store.providers.count))
        let tucked = settings.autoHide && !notchRevealed
        let visibleWidth = tucked ? Theme.autoHideSliver : size.width
        let frame = NSRect(
            x: screen.frame.maxX - visibleWidth,
            y: screen.visibleFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                notchPanel.animator().setFrame(frame, display: true)
            }
        } else {
            notchPanel.setFrame(frame, display: true)
        }
    }

    // MARK: - Auto-hide

    private func notchHoverChanged(inside: Bool) {
        pointerInsideNotch = inside
        guard settings.autoHide else { return }
        if inside {
            tuckNotchTask?.cancel()
            if !notchRevealed {
                notchRevealed = true
                applyNotchFrame(animated: true)
            }
        } else {
            scheduleTuck()
        }
    }

    private func scheduleTuck() {
        tuckNotchTask?.cancel()
        tuckNotchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            // Never tuck while the pointer rests anywhere on the notch —
            // including the flare areas that belong to no provider cell.
            guard self.settings.autoHide, !self.pointerInsideNotch, self.hoverModel.hover == nil else { return }
            self.notchRevealed = false
            self.applyNotchFrame(animated: true)
        }
    }

    // MARK: - Menu bar

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "gauge.with.needle",
            accessibilityDescription: "AI Side Notch"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if store.providers.isEmpty {
            menu.addItem(disabledItem("No providers configured"))
        }
        for info in store.providers {
            let label = switch store.states[info.id] {
            case let .ok(status): status.ringLabel
            case .failed: "error"
            default: "…"
            }
            menu.addItem(disabledItem("\(info.name) — \(label)"))
        }
        menu.addItem(.separator())
        menu.addItem(makeItem("Refresh Now", action: #selector(refreshNow), key: "r"))
        menu.addItem(makeItem("Settings…", action: #selector(openSettingsFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit AI Side Notch", action: #selector(quitApp), key: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refreshNow() {
        Task { await store.refreshAll(force: true) }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
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
        var y = anchorY - size.height / 2
        if let visible = screen?.visibleFrame {
            // Keep the card fully on screen (the top ring sits near the menu bar).
            y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        // Anchor to the notch's settled (revealed) x, not the live frame —
        // during an auto-hide reveal the real frame lags behind and the card
        // would land on top of the notch. The shadow margin overlaps the gap
        // so the pointer sits cardGap from the notch.
        let notchMinX = screen.map { $0.frame.maxX - metrics.bodyWidth } ?? notchPanel.frame.minX
        let origin = NSPoint(
            x: notchMinX - size.width - Theme.cardGap + Theme.cardShadowPad,
            y: y
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
            window.title = "AI Side Notch Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        let firstOpen = settingsWindow?.contentView == nil
        // Fresh root view each open so key fields re-read the Keychain and
        // provider detection reflects CLIs signed into since launch.
        store.reloadProviders()
        Task { await store.refreshAll() }
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(store: store, settings: settings))
        if firstOpen { settingsWindow?.center() }
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
                .padding(Theme.cardShadowPad)
        }
    }
}

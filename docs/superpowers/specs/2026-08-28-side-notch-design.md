# AI Usage Side Notch — Design

Date: 2026-08-28
Status: Approved for implementation (autonomous session; decisions recorded here for review)

## Goal

A macOS "side notch" — a black, pill-flared panel attached to the right edge of the
screen — that shows AI usage at a glance for several major AI platforms:

- Up to **3 providers visible at a time**, with **smooth snap scrolling** through all
  configured providers.
- Each provider renders as a **ring gauge** (usage %) with the provider glyph inside
  and a label underneath.
- **Hovering** a provider expands a **detail card** to the left (mirroring the mock):
  metric rows with progress bars, reset times ("Resets in 51 min", "Resets Thu 12:00 AM"),
  and **available API credits / balance** where the provider exposes it.
- Minimal, clean, dependency-free codebase that anyone can build with `swift build`.

## Architecture

Swift Package Manager executable (`SideNotch`), zero third-party dependencies,
macOS 14+. SwiftUI for all drawing; a thin AppKit shell for the borderless panel.

```
Sources/SideNotch/
  App/        AppDelegate + NotchPanel (borderless, non-activating NSPanel, right edge)
  UI/         NotchShape, RingGauge, DetailCard, ProviderGlyph, NotchView (scroll+snap)
  Core/       Models (ProviderStatus, Metric), UsageStore, Formatting, Keychain, HTTP
  Providers/  ClaudeProvider, CodexProvider, OpenRouterProvider, DeepSeekProvider
Tests/SideNotchTests/   parsing, formatting, ring math
scripts/make-app.sh     wraps the SPM binary into SideNotch.app (LSUIElement)
```

### Window behavior

- `NSPanel` with `[.borderless, .nonactivatingPanel]`, `.statusBar` level, clear
  background, joins all Spaces. Pinned flush to the right edge of the primary screen,
  top-anchored just below the menu bar.
- The window is exactly as wide as the notch. On hover it grows leftward to fit the
  detail card (right edge stays pinned), and shrinks back when the pointer leaves.
  This keeps transparent regions from swallowing clicks meant for windows beneath.
- Right-click on the notch: Refresh, Settings…, Quit.

### Snap scrolling

SwiftUI `ScrollView` + `scrollTargetLayout()` + `.scrollTargetBehavior(.viewAligned)`;
viewport is exactly 3 item-heights tall, so trackpad scrolling glides and settles on
item boundaries. Indicators hidden.

### Provider model

```swift
protocol UsageProvider: Sendable {
    var info: ProviderInfo { get }          // id, name, glyph
    func isConfigured() -> Bool             // credentials present?
    func fetch() async throws -> ProviderStatus
}

struct ProviderStatus {   // what the UI renders
    var ringFraction: Double?     // nil → balance-only provider (full ring)
    var ringLabel: String         // "73%" or "$12.40"
    var metrics: [Metric]         // rows in the hover card
    var credits: String?          // "Balance $12.40" row when available
}

struct Metric { label; sublabel /* "Resets in 51 min" */; fraction; footnote }
```

`UsageStore` (`@MainActor ObservableObject`) refreshes every 60 s and on demand,
holding per-provider `LoadState` (loading / ok / error). Ring color derives from
usage: <35% green, <70% yellow, ≥70% red-orange — matching the mock's palette.

### Providers (initial set)

| Provider   | Data                                            | Credentials |
|------------|--------------------------------------------------|-------------|
| Claude     | Claude Code 5-hour session + weekly utilization % and reset times (same numbers as `/usage`) | Reuses Claude Code's OAuth token (Keychain / `~/.claude/.credentials.json`) |
| OpenAI (Codex/ChatGPT) | Codex CLI rate-limit windows: used % + resets | Reuses Codex CLI auth (`~/.codex/auth.json`) |
| OpenRouter | Credits balance + usage vs. purchased credits    | API key (Settings) |
| DeepSeek   | Account balance                                  | API key (Settings) |

Exact endpoints/schemas verified against official docs and community source before
implementation (research workflow). Providers that expose no balance show usage only;
balance-only providers show the balance as the ring label.

### Settings

Small SwiftUI window: per-provider enable toggles and API-key fields. Keys live in
the login Keychain (never UserDefaults). Claude/Codex rows auto-detect their CLIs'
credentials and need no key entry.

### Error handling

A provider that is enabled but unconfigured or failing renders a dimmed ring with a
warning glyph; details in the hover card. Network errors never crash the panel; the
store keeps the last good status and retries on the next tick.

### Testing

- Unit tests (pure logic, no network): response decoding from captured fixtures for
  every provider; reset-time formatting; ring fraction clamping/color thresholds.
- `swift build` + launch smoke test (app boots, panel appears, quits cleanly).

### Out of scope (YAGNI)

Multi-display placement options, drag-to-reposition, notifications/alerts, per-model
breakdowns, Windows/Linux.

# AI Usage Side Notch

A macOS **side notch** that lives on the right edge of your screen and shows, at a
glance, how much of your AI usage limits you've burned — across several major AI
platforms at once.

- **Ring gauges** per provider (green → yellow → red as usage climbs), up to
  **3 visible at a time**, with **smooth snap scrolling** through all of them.
- **Hover** a ring to expand a detail card: session/weekly usage bars, reset
  times ("Resets in 51 min"), and **API credits / balance** where the provider
  exposes it.
- Always on top, on every Space, and never steals focus or clicks.
- Zero dependencies. One small Swift package.

## Supported providers

| Provider | What it shows | Setup |
|---|---|---|
| **Claude** | Claude Code 5-hour session + weekly usage %, reset times (same numbers as `/usage`) | None — auto-detects your Claude Code login |
| **OpenAI** | Codex/ChatGPT plan 5-hour + weekly rate-limit usage %, credits balance | None — auto-detects your Codex CLI login (`codex login`) |
| **OpenRouter** | Usage vs. key limit / purchased credits, remaining balance, daily–monthly spend | API key in Settings |
| **DeepSeek** | Account balance (granted + topped-up) | API key in Settings |

Providers appear automatically once their credentials exist; scroll the notch to
flip through them. Right-click the notch for **Refresh / Settings / Quit**.

> Claude and OpenAI data comes from the same endpoints their own CLIs use. These
> are unofficial and may change. The Claude endpoint is polled gently (every
> 5 min) per its rate-limit rules; on first launch macOS may ask permission for
> the app to read Claude Code's Keychain item.

## Install

```bash
git clone https://github.com/AngeloLandiza/MacOS-AI-Usage-Side-Notch-Tracker.git
cd MacOS-AI-Usage-Side-Notch-Tracker
scripts/make-app.sh
open dist/SideNotch.app
```

Requires macOS 14+ and Xcode 16+ (`swift build` needs the full Xcode toolchain
for SwiftUI, not just the Command Line Tools — if you see a `SwiftUIMacros`
error, run `sudo xcode-select -s /Applications/Xcode.app`).

For development: `swift run` (add `--scratch-path /tmp/sidenotch` if your
checkout lives in an iCloud-synced folder like Documents, where Finder metadata
breaks codesigning).

## Test

```bash
swift test
```

Unit tests cover every provider's response parsing (fixtures captured from real
responses), reset-time formatting, and ring math.

## Design

See [docs/superpowers/specs/2026-08-28-side-notch-design.md](docs/superpowers/specs/2026-08-28-side-notch-design.md).
The codebase is deliberately small:

```
Sources/SideNotch/
  App/        app shell: borderless panels, settings window
  UI/         notch shape, ring gauge, detail card, snap-scrolling column
  Core/       models, store, formatting, keychain, http
  Providers/  one small file per AI platform
```

Adding a provider = one file implementing `UsageProvider` (identity + `fetch()`
returning a `ProviderStatus`) plus one line in `ProviderRegistry`.

## License

MIT — see [LICENSE](LICENSE).

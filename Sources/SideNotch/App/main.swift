import AppKit

// `SideNotch --dump` prints every provider's live status and exits — handy for
// checking credentials and API access without watching the notch.
if CommandLine.arguments.contains("--dump") {
    Task { @MainActor in
        for provider in ProviderRegistry.all {
            guard provider.isConfigured() else {
                print("\(provider.info.name): not configured")
                continue
            }
            do {
                let status = try await provider.fetch()
                let rows = status.metrics
                    .map { m in "\(m.label): \(m.footnote ?? m.sublabel ?? "")" }
                    .joined(separator: " | ")
                print("\(provider.info.name): ring \(status.ringLabel)"
                    + (rows.isEmpty ? "" : " — \(rows)")
                    + (status.credits.map { " — credits \($0)" } ?? ""))
            } catch {
                print("\(provider.info.name): ERROR — \(error.localizedDescription)")
            }
        }
        exit(0)
    }
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

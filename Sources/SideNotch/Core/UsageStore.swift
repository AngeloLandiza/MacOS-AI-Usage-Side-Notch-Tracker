import Foundation
import SwiftUI

/// Holds the latest state for every configured provider and refreshes each one
/// on its own cadence (some endpoints throttle aggressive pollers).
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var providers: [ProviderInfo] = []
    @Published private(set) var states: [String: LoadState] = [:]

    private var byID: [String: any UsageProvider] = [:]
    private var lastFetch: [String: Date] = [:]
    private var timer: Timer?

    private static let tickInterval: TimeInterval = 30

    func start() {
        reloadProviders()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { _ in
            Task { @MainActor in await self.refreshDue() }
        }
        Task { await refreshAll(force: true) }
    }

    /// Re-detects configured providers (called after Settings changes).
    func reloadProviders() {
        let configured = ProviderRegistry.configured
        byID = Dictionary(uniqueKeysWithValues: configured.map { ($0.info.id, $0) })
        providers = configured.map(\.info)
        for info in providers where states[info.id] == nil {
            states[info.id] = .loading
        }
        states = states.filter { byID[$0.key] != nil }
    }

    func refreshAll(force: Bool = false) async {
        await refresh(ids: Array(byID.keys), force: force)
    }

    private func refreshDue() async {
        let now = Date()
        let due = byID.filter { id, provider in
            now.timeIntervalSince(lastFetch[id] ?? .distantPast) >= provider.refreshInterval
        }
        await refresh(ids: Array(due.keys), force: false)
    }

    private func refresh(ids: [String], force: Bool) async {
        let now = Date()
        var targets: [(String, any UsageProvider)] = []
        for id in ids {
            guard let provider = byID[id] else { continue }
            if !force, now.timeIntervalSince(lastFetch[id] ?? .distantPast) < provider.refreshInterval {
                continue
            }
            lastFetch[id] = now
            targets.append((id, provider))
        }
        // Fetch concurrently off the main actor, then apply results here.
        let results = await withTaskGroup(of: (String, Result<ProviderStatus, any Error>).self) { group in
            for (id, provider) in targets {
                group.addTask {
                    do { return (id, .success(try await provider.fetch())) }
                    catch { return (id, .failure(error)) }
                }
            }
            var collected: [(String, Result<ProviderStatus, any Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        for (id, result) in results {
            switch result {
            case let .success(status):
                states[id] = .ok(status)
            case let .failure(error):
                // Keep the last good value if we had one; otherwise surface the error.
                if case .ok = states[id] { continue }
                states[id] = .failed(error.localizedDescription)
            }
        }
    }
}

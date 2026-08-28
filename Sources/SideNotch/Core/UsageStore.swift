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
    private var failureStreak: [String: Int] = [:]
    private var timer: Timer?

    /// Keep showing last-good data through this many failed refreshes, then
    /// surface the error (e.g. an expired login) instead of stale numbers.
    private static let maxMaskedFailures = 3

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
        lastFetch = lastFetch.filter { byID[$0.key] != nil }
        failureStreak = failureStreak.filter { byID[$0.key] != nil }
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
            // The provider may have been removed in Settings mid-fetch.
            guard byID[id] != nil else { continue }
            switch result {
            case let .success(status):
                failureStreak[id] = 0
                states[id] = .ok(status)
            case let .failure(error):
                // Keep the last good value through transient errors, but stop
                // masking once failures persist.
                let streak = (failureStreak[id] ?? 0) + 1
                failureStreak[id] = streak
                if case .ok = states[id], streak < Self.maxMaskedFailures { continue }
                states[id] = .failed(error.localizedDescription)
            }
        }
    }
}

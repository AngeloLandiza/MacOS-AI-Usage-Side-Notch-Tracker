import Foundation
import Testing
@testable import SideNotch

// Fixtures mirror real captured responses (values anonymized).

@Suite struct ClaudeParsingTests {
    static let fixture = Data("""
    {
      "five_hour": {"utilization": 73.0, "resets_at": "2026-08-28T12:13:00.528743+00:00"},
      "seven_day": {"utilization": 7.0, "resets_at": "2026-09-03T04:00:00.951713+00:00"},
      "seven_day_opus": null,
      "seven_day_oauth_apps": null,
      "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null}
    }
    """.utf8)

    @Test func parsesSessionAndWeekly() throws {
        let now = ISO8601DateFormatter().date(from: "2026-08-28T11:22:00+00:00")!
        let status = try ClaudeProvider.parse(Self.fixture, now: now)
        #expect(status.ringFraction == 0.73)
        #expect(status.ringLabel == "73%")
        #expect(status.metrics.count == 2)
        #expect(status.metrics[0].label == "Current session")
        #expect(status.metrics[0].sublabel == "Resets in 51 min")
        #expect(status.metrics[0].footnote == "73% Used")
        #expect(status.metrics[1].label == "All models")
        #expect(status.metrics[1].fraction == 0.07)
        #expect(status.credits == nil)
    }

    @Test func normalizesFractionalUtilization() {
        // A fractional 0–1 value means the API reported a ratio, not a percent.
        #expect(ClaudeProvider.normalizedUtilization(0.5) == 0.5)
        #expect(ClaudeProvider.normalizedUtilization(45.2) == 0.452)
        #expect(ClaudeProvider.normalizedUtilization(250) == 1.0)
        #expect(ClaudeProvider.normalizedUtilization(0) == 0)
    }

    @Test func includesEnabledExtraUsage() throws {
        let data = Data("""
        {"five_hour": {"utilization": 10, "resets_at": null},
         "extra_usage": {"is_enabled": true, "monthly_limit": 50.0, "used_credits": 12.5, "utilization": 25}}
        """.utf8)
        let status = try ClaudeProvider.parse(data)
        let extra = try #require(status.metrics.last)
        #expect(extra.label == "Extra usage")
        #expect(extra.sublabel == "$12.50 of $50.00")
    }
}

@Suite struct CodexParsingTests {
    static let fixture = Data("""
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {"used_percent": 21, "limit_window_seconds": 18000, "reset_after_seconds": 8657, "reset_at": 1766948068},
        "secondary_window": {"used_percent": 43, "limit_window_seconds": 604800, "reset_after_seconds": 187681, "reset_at": 1767407914}
      },
      "credits": {"has_credits": true, "unlimited": false, "overage_limit_reached": false, "balance": "4.25"}
    }
    """.utf8)

    @Test func parsesWindowsAndCredits() throws {
        let status = try CodexProvider.parse(Self.fixture)
        #expect(status.ringFraction == 0.21)
        #expect(status.ringLabel == "21%")
        #expect(status.metrics.count == 2)
        #expect(status.metrics[0].label == "Current session")
        #expect(status.metrics[1].label == "Weekly")
        #expect(status.metrics[1].fraction == 0.43)
        #expect(status.credits == "$4.25")
    }

    @Test func toleratesMissingBlocks() throws {
        let status = try CodexProvider.parse(Data("{}".utf8))
        #expect(status.ringFraction == 0)
        #expect(status.metrics.isEmpty)
        #expect(status.credits == nil)
    }

    @Test func zeroScientificBalanceHidden() throws {
        let data = Data("""
        {"rate_limit": {"primary_window": {"used_percent": 5}},
         "credits": {"has_credits": false, "unlimited": false, "balance": "0E-10"}}
        """.utf8)
        let status = try CodexProvider.parse(data)
        #expect(status.credits == nil)
    }
}

@Suite struct OpenRouterParsingTests {
    static let keyFixture = Data("""
    {"data": {"label": "sk-or-v1-au7...890", "limit": 100, "limit_reset": "monthly",
      "limit_remaining": 74.5, "usage": 25.5, "usage_daily": 1.25, "usage_weekly": 8.0,
      "usage_monthly": 25.5, "is_free_tier": false}}
    """.utf8)
    static let creditsFixture = Data("""
    {"data": {"total_credits": 100.5, "total_usage": 25.75}}
    """.utf8)

    @Test func usesKeyLimitForRing() throws {
        let status = try OpenRouterProvider.parse(keyData: Self.keyFixture, creditsData: Self.creditsFixture)
        #expect(status.ringFraction != nil)
        #expect(abs(status.ringFraction! - 0.255) < 0.001)
        #expect(status.ringLabel == "26%")
        #expect(status.credits == "$74.75")
        #expect(status.metrics.map(\.label) == ["Today", "This week", "This month"])
    }

    @Test func uncappedKeyWithoutCreditsShowsBalanceFromKey() throws {
        let key = Data("""
        {"data": {"limit": null, "limit_remaining": 12.4, "usage": 3.2, "usage_daily": 0.5}}
        """.utf8)
        let status = try OpenRouterProvider.parse(keyData: key, creditsData: nil)
        #expect(status.ringFraction == nil)
        #expect(status.ringLabel == "$12.40")
        #expect(status.credits == "$12.40")
    }

    @Test func creditsFallbackWhenNoKeyCap() throws {
        let key = Data(#"{"data": {"limit": null, "usage": 25.75}}"#.utf8)
        let status = try OpenRouterProvider.parse(keyData: key, creditsData: Self.creditsFixture)
        #expect(abs(status.ringFraction! - 0.2562) < 0.001)
        #expect(status.credits == "$74.75")
    }
}

@Suite struct DeepSeekParsingTests {
    static let fixture = Data("""
    {"is_available": true, "balance_infos": [
      {"currency": "USD", "total_balance": "110.00", "granted_balance": "10.00", "topped_up_balance": "100.00"}
    ]}
    """.utf8)

    @Test func parsesBalance() throws {
        let status = try DeepSeekProvider.parse(Self.fixture)
        #expect(status.ringFraction == nil)   // balance-only: full ring
        #expect(status.ringLabel == "$110")
        #expect(status.credits == "$110")
        #expect(status.metrics.count == 2)
    }

    @Test func exhaustedBalanceShowsEmptyRing() throws {
        let data = Data("""
        {"is_available": false, "balance_infos": [
          {"currency": "USD", "total_balance": "0.00", "granted_balance": "0.00", "topped_up_balance": "0.00"}]}
        """.utf8)
        let status = try DeepSeekProvider.parse(data)
        #expect(status.ringFraction == 0)
        #expect(status.metrics.contains { $0.label == "Balance exhausted" })
    }
}

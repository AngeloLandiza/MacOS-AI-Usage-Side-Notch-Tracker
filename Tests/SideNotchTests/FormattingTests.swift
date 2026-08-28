import Foundation
import Testing
@testable import SideNotch

@Suite struct FormattingTests {
    let utc = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func percentRoundsAndClamps() {
        #expect(Fmt.percent(0.73) == "73%")
        #expect(Fmt.percent(0.005) == "1%")
        #expect(Fmt.percent(0) == "0%")
        #expect(Fmt.percent(1.7) == "100%")
        #expect(Fmt.percent(-0.2) == "0%")
    }

    @Test func moneyFormats() {
        #expect(Fmt.money(12.4) == "$12.40")
        #expect(Fmt.money(0) == "$0.00")
        #expect(Fmt.money(110) == "$110")
        #expect(Fmt.money(1204.6) == "$1,205")
    }

    @Test func resetWithinTheHour() {
        let now = date("2026-08-27T11:22:00Z")
        #expect(Fmt.reset(date("2026-08-27T12:13:00Z"), now: now, calendar: utc) == "Resets in 51 min")
        #expect(Fmt.reset(date("2026-08-27T11:22:30Z"), now: now, calendar: utc) == "Resets in <1 min")
    }

    @Test func resetWithinTheDay() {
        let now = date("2026-08-27T11:22:00Z")
        #expect(Fmt.reset(date("2026-08-27T14:42:00Z"), now: now, calendar: utc) == "Resets in 3 hr 20 min")
        #expect(Fmt.reset(date("2026-08-27T13:22:00Z"), now: now, calendar: utc) == "Resets in 2 hr")
    }

    @Test func resetBeyondADayShowsWeekday() {
        let now = date("2026-08-25T11:22:00Z")
        // 2026-08-27 is a Thursday.
        #expect(Fmt.reset(date("2026-08-27T00:00:00Z"), now: now, calendar: utc) == "Resets Thu 12:00 AM")
    }

    @Test func pastResetIsGraceful() {
        let now = date("2026-08-27T11:22:00Z")
        #expect(Fmt.reset(date("2026-08-27T11:00:00Z"), now: now, calendar: utc) == "Resets soon")
    }

    @Test func isoDateParsingBothVariants() {
        #expect(parseISODate("2026-08-28T22:00:00.528743+00:00") != nil)
        #expect(parseISODate("2026-08-28T22:00:00+00:00") != nil)
        #expect(parseISODate("not a date") == nil)
    }
}

@Suite struct RingMathTests {
    @Test func unitClamping() {
        #expect((-0.5).unitClamped == 0)
        #expect(0.42.unitClamped == 0.42)
        #expect(3.0.unitClamped == 1)
    }

    @Test func usageColorThresholds() {
        #expect(usageColor(fraction: 0.21) == usageColor(fraction: 0.0))    // green band
        #expect(usageColor(fraction: 0.52) == usageColor(fraction: 0.69))   // yellow band
        #expect(usageColor(fraction: 0.73) == usageColor(fraction: 1.0))    // red band
        #expect(usageColor(fraction: 0.21) != usageColor(fraction: 0.73))
        #expect(usageColor(fraction: nil) == usageColor(fraction: nil))     // balance-only: stable
    }

    @Test func notchHeightCapsAtThreeItems() {
        let one = Theme.notchHeight(itemCount: 1)
        let three = Theme.notchHeight(itemCount: 3)
        #expect(Theme.notchHeight(itemCount: 0) == one)   // empty state still shows one cell
        #expect(Theme.notchHeight(itemCount: 5) == three) // never taller than 3 visible
        #expect(three - one == 2 * Theme.itemHeight)
    }
}

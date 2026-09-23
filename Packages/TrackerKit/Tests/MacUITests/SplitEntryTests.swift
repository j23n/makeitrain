#if os(macOS)
import Foundation
import Testing
import TrackerCore
@testable import MacUI

@Suite struct SplitEntryTests {
    let now = DateTimeFormat.parse("2026-09-23T15:40:00+02:00")!

    /// An entry on September 23 in Berlin, such as from "13:00" to "17:00",
    /// or running without an end.
    func entry(_ start: String, _ end: String?) -> ResolvedEntry {
        let startTime = DateTimeFormat.parse("2026-09-23T\(start):00+02:00")!
        let endTime = end.map { DateTimeFormat.parse("2026-09-23T\($0):00+02:00")! }
        let entry = TimeEntry(start: startTime, end: endTime, timeZone: "Europe/Berlin", updated: startTime)
        return Ledger(entries: [entry]).resolvedEntries()[0]
    }

    func time(_ text: String) -> Date {
        DateTimeFormat.parse("2026-09-23T\(text):00+02:00")!.date
    }

    @Test func suggestsTheMiddleOnFiveMinutes() {
        #expect(SplitEntrySheet.suggestedTime(for: entry("13:00", "17:00"), now: now) == time("15:00"))
        #expect(SplitEntrySheet.suggestedTime(for: entry("13:00", "14:10"), now: now) == time("13:35"))
        // The running timer counts as ending now.
        #expect(SplitEntrySheet.suggestedTime(for: entry("14:45", nil), now: now) == time("15:15"))
        // No five minutes inside it: the middle, on a minute.
        #expect(SplitEntrySheet.suggestedTime(for: entry("09:01", "09:04"), now: now) == time("09:03"))
    }

    @Test func splitsOnlyInsideTheEntry() {
        #expect(SplitEntrySheet.range(of: entry("09:00", "10:00"), now: now) == time("09:01")...time("09:59"))
        #expect(SplitEntrySheet.range(of: entry("09:00", "09:01"), now: now) == nil)
        #expect(SplitEntrySheet.range(of: entry("15:39", nil), now: now) == nil)
    }
}
#endif

#if os(macOS)
import Foundation
import Testing
import TrackerCore
@testable import MacUI

@Suite struct EntriesExportTests {
    /// An hour from each start, such as "2026-09-23T09:00:00+02:00", in the
    /// zone given with it.
    func entries(_ starts: [(String, String)]) -> [ResolvedEntry] {
        Ledger(entries: starts.map { start, zone in
            let time = DateTimeFormat.parse(start)!
            return TimeEntry(start: time, end: time.adding(seconds: 3600), timeZone: zone, updated: time)
        }).resolvedEntries()
    }

    @Test func namesTheFileForTheDaysItCovers() {
        #expect(EntriesExport.fileName(for: []) == nil)
        #expect(EntriesExport.fileName(for: entries([("2026-09-23T09:00:00+02:00", "Europe/Berlin")])) == "Time Entries 2026-09-23")
        #expect(EntriesExport.fileName(for: entries([
            ("2026-09-23T09:00:00+02:00", "Europe/Berlin"),
            ("2025-03-04T09:00:00+01:00", "Europe/Berlin"),
            // Its own day, though it's October 1 in UTC.
            ("2026-09-30T22:00:00-04:00", "America/New_York"),
        ])) == "Time Entries 2025-03-04 to 2026-09-30")
    }
}
#endif

import Foundation
import Testing
@testable import TrackerCore

@Suite struct EntryFilterTests {
    let now = t("2026-09-23T12:00:00Z")

    func day(_ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: 9, day: day)
    }

    func entry(_ id: Int, _ start: String, zone: String) -> TimeEntry {
        let time = t(start)
        return TimeEntry(id: uuid(id), start: time, end: time.adding(seconds: 1800), timeZone: zone, updated: now)
    }

    @Test func goesByTheDayInTheEntrysOwnZone() {
        let ledger = Ledger(entries: [
            // The 22nd at UTC+14, still the 21st in UTC.
            entry(1, "2026-09-22T00:30:00+14:00", zone: "Pacific/Kiritimati"),
            // The 21st at UTC-12, already the 22nd in UTC.
            entry(2, "2026-09-21T23:30:00-12:00", zone: "Etc/GMT+12"),
            entry(3, "2026-09-23T12:00:00+02:00", zone: "Europe/Berlin"),
            // The 25th at UTC+14, still the 24th in UTC.
            entry(4, "2026-09-25T00:30:00+14:00", zone: "Pacific/Kiritimati"),
            // The 24th at UTC-12, already the 25th in UTC.
            entry(5, "2026-09-24T23:30:00-12:00", zone: "Etc/GMT+12"),
            entry(6, "2026-09-10T12:00:00+02:00", zone: "Europe/Berlin"),
        ])
        let resolved = ledger.resolvedEntries()
        let matches = EntryFilter(range: day(22)...day(24)).matcher(in: ledger)
        let onThoseDays: Set<UUID> = [uuid(1), uuid(3), uuid(5)]
        #expect(Set(resolved.filter(matches).map(\.id)) == onThoseDays)
    }

    @Test func findsTheSameDaysAsLookingUpEachZone() {
        var generator = SeededGenerator(seed: 7)
        let zones = ["Pacific/Kiritimati", "Etc/GMT+12", "America/New_York", "Europe/Berlin", "Asia/Kolkata", "UTC"]
        let base = t("2026-09-18T00:00:00Z")
        let entries = (0..<600).map { index in
            let start = base.adding(seconds: Int64(generator.next() % (14 * 86_400)))
            return TimeEntry(
                id: uuid(index + 1), start: start, end: start.adding(seconds: 600),
                timeZone: zones[Int(generator.next() % UInt64(zones.count))], updated: now
            )
        }
        let ledger = Ledger(entries: entries)
        let resolved = ledger.resolvedEntries()
        for range in [day(22)...day(22), day(21)...day(25), day(18)...day(30), day(1)...day(19)] {
            let matches = EntryFilter(range: range).matcher(in: ledger)
            let expected = resolved.filter { range.contains($0.entry.day) }.map(\.id)
            #expect(resolved.filter(matches).map(\.id) == expected)
        }
    }
}

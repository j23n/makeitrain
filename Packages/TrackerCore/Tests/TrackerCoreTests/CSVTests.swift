import Foundation
import Testing
@testable import TrackerCore

@Suite struct CSVTests {
    let now = t("2026-09-25T18:00:00+02:00")

    var ledger: Ledger {
        Ledger(
            clients: [Client(id: uuid(20), name: "Acme, Inc.", updated: now)],
            projects: [
                Project(id: uuid(10), clientID: uuid(20), name: "Website", updated: now),
                Project(id: uuid(11), name: "Internal", updated: now),
            ]
        )
    }

    func csv(_ entries: [TimeEntry]) -> String {
        var ledger = ledger
        for entry in entries { ledger.merge(entry) }
        let range = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
        return CSVExport.text(for: Report(ReportRequest(range: range), ledger: ledger).entries, ledger: ledger)
    }

    func lines(_ text: String) -> [String] {
        text.dropFirst().components(separatedBy: "\r\n")
    }

    @Test func writesOneRowPerEntryWithAHeader() {
        let text = csv([
            TimeEntry(
                id: uuid(1), projectID: uuid(10),
                start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T11:25:00+02:00"),
                timeZone: "Europe/Berlin", tags: ["design", "call"], note: "Kickoff", updated: now
            ),
            TimeEntry(
                id: uuid(2), projectID: uuid(11),
                start: t("2026-09-23T13:00:00+02:00"), end: t("2026-09-23T13:10:00+02:00"),
                timeZone: "Europe/Berlin", updated: now
            ),
            TimeEntry(
                id: uuid(3),
                start: t("2026-09-24T22:00:00-04:00"), end: t("2026-09-24T23:00:00-04:00"),
                timeZone: "America/New_York", updated: now
            ),
        ])

        #expect(text.hasPrefix("\u{FEFF}date,start,end,hours,client,project,tags,note\r\n"))
        #expect(text.hasSuffix("\r\n"))
        #expect(lines(text) == [
            "date,start,end,hours,client,project,tags,note",
            "2026-09-23,2026-09-23T09:00:00+02:00,2026-09-23T11:25:00+02:00,2.4167,\"Acme, Inc.\",Website,design;call,Kickoff",
            "2026-09-23,2026-09-23T13:00:00+02:00,2026-09-23T13:10:00+02:00,0.1667,,Internal,,",
            // Its own day and offset, though it's the 25th in UTC.
            "2026-09-24,2026-09-24T22:00:00-04:00,2026-09-24T23:00:00-04:00,1.0000,,,,",
            "",
        ])
    }

    @Test func quotesFieldsThatNeedIt() {
        let text = csv([
            TimeEntry(
                id: uuid(1), start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"),
                timeZone: "Europe/Berlin", tags: ["a;b", "c"], note: "Said \"hi\", then\r\nleft\nfor lunch", updated: now
            ),
        ])

        #expect(text == "\u{FEFF}date,start,end,hours,client,project,tags,note\r\n"
            + "2026-09-23,2026-09-23T09:00:00+02:00,2026-09-23T10:00:00+02:00,1.0000,,,ab;c,\"Said \"\"hi\"\", then\r\nleft\nfor lunch\"\r\n")
    }

    @Test func leavesOutTheRunningTimer() {
        let text = csv([
            TimeEntry(id: uuid(1), start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"), timeZone: "Europe/Berlin", updated: now),
            TimeEntry(id: uuid(2), start: t("2026-09-25T17:00:00+02:00"), timeZone: "Europe/Berlin", updated: now),
        ])

        #expect(lines(text).count == 3)
    }

    @Test func writesEveryEntryButARunningTimer() {
        var ledger = ledger
        for entry in [
            TimeEntry(id: uuid(1), start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"), timeZone: "Europe/Berlin", updated: now),
            TimeEntry(id: uuid(2), start: t("2025-03-04T09:00:00+01:00"), end: t("2025-03-04T09:30:00+01:00"), timeZone: "Europe/Berlin", updated: now),
            TimeEntry(id: uuid(3), start: t("2026-09-25T17:00:00+02:00"), timeZone: "Europe/Berlin", updated: now),
        ] {
            ledger.merge(entry)
        }

        let rows = lines(CSVExport.text(for: ledger.resolvedEntries(), ledger: ledger))
        #expect(rows == [
            "date,start,end,hours,client,project,tags,note",
            "2025-03-04,2025-03-04T09:00:00+01:00,2025-03-04T09:30:00+01:00,0.5000,,,,",
            "2026-09-23,2026-09-23T09:00:00+02:00,2026-09-23T10:00:00+02:00,1.0000,,,,",
            "",
        ])
    }

    @Test func namesTheFileOfEntriesForTheDaysItCovers() {
        func entries(_ starts: [(String, String)]) -> [ResolvedEntry] {
            Ledger(entries: starts.map { start, zone in
                TimeEntry(start: t(start), end: t(start).adding(seconds: 3600), timeZone: zone, updated: now)
            }).resolvedEntries()
        }
        #expect(CSVExport.fileName(for: []) == nil)
        #expect(CSVExport.fileName(for: entries([("2026-09-23T09:00:00+02:00", "Europe/Berlin")])) == "Time Entries 2026-09-23")
        #expect(CSVExport.fileName(for: entries([
            ("2026-09-23T09:00:00+02:00", "Europe/Berlin"),
            ("2025-03-04T09:00:00+01:00", "Europe/Berlin"),
            // Its own day, though it's October 1 in UTC.
            ("2026-09-30T22:00:00-04:00", "America/New_York"),
        ])) == "Time Entries 2025-03-04 to 2026-09-30")
    }

    @Test func roundsHoursToFourDecimals() {
        #expect(CSVExport.hours(0) == "0.0000")
        #expect(CSVExport.hours(1000) == "0.0003")
        #expect(CSVExport.hours(20_000) == "0.0056")
        #expect(CSVExport.hours(3_600_000) == "1.0000")
        // 0.00005 hours rounds up.
        #expect(CSVExport.hours(180) == "0.0001")
        #expect(CSVExport.hours(179) == "0.0000")
        #expect(CSVExport.hours(36_000_000 * 100) == "1000.0000")
        #expect(CSVExport.hours(-5) == "0.0000")
    }

    @Test func theHoursColumnAddsUpToTheTotal() {
        var rng = SeededGenerator(seed: 7)
        var entries: [TimeEntry] = []
        var start = t("2026-09-21T08:00:00+02:00")
        for number in 1...40 {
            let length = Int64(rng.next() % 7200) + 1
            entries.append(TimeEntry(
                id: uuid(number), start: start, end: start.adding(seconds: length),
                timeZone: "Europe/Berlin", updated: now
            ))
            start = start.adding(seconds: length + Int64(rng.next() % 3600))
        }
        var ledger = ledger
        for entry in entries { ledger.merge(entry) }
        let range = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
        let report = Report(ReportRequest(range: range), ledger: ledger)
        let rows = lines(CSVExport.text(for: report.entries, ledger: ledger)).dropFirst().dropLast()
        let tenThousandths = rows.map { row -> Int64 in
            let hours = row.split(separator: ",", omittingEmptySubsequences: false)[3].split(separator: ".")
            return Int64(hours[0])! * 10000 + Int64(hours[1])!
        }.reduce(0, +)

        // Each row is off by at most half a ten-thousandth of an hour (0.18 s).
        #expect(rows.count == 40)
        #expect(abs(tenThousandths * 360 - report.total) <= 40 * 180)
        // The total of the column is what the rows add up to.
        #expect(CSVExport.totalHours(report.entries) == "\(tenThousandths / 10000).\(padded(Int(tenThousandths % 10000), 4))")
    }

    @Test func addsUpTheHoursColumnRowByRow() {
        var ledger = ledger
        let start = t("2026-09-23T09:00:00+02:00")
        for number in 1...3 {
            // 20 seconds, which a row writes as 0.0056 hours.
            let from = start.adding(seconds: Int64(number) * 60)
            ledger.merge(TimeEntry(id: uuid(number), start: from, end: from.adding(seconds: 20), timeZone: "Europe/Berlin", updated: now))
        }
        // A running timer isn't a row.
        ledger.merge(TimeEntry(id: uuid(4), start: t("2026-09-25T17:00:00+02:00"), timeZone: "Europe/Berlin", updated: now))

        #expect(CSVExport.totalHours(ledger.resolvedEntries()) == "0.0168")
        #expect(CSVExport.totalHours([]) == "0.0000")
    }
}

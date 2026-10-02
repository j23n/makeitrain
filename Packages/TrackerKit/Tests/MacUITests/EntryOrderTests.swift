#if os(macOS)
import Foundation
import Testing
import TrackerCore
@testable import MacUI

@Suite struct EntryOrderTests {
    /// A row for an entry on September 23 in Berlin, from a time such as
    /// "09:00" to another, or running, with its project's title.
    func row(_ note: String, project: String, from start: String, to end: String?) -> EntryRow {
        let startTime = DateTimeFormat.parse("2026-09-23T\(start):00+02:00")!
        let endTime = end.map { DateTimeFormat.parse("2026-09-23T\($0):00+02:00")! }
        let entry = TimeEntry(start: startTime, end: endTime, timeZone: "Europe/Berlin", note: note, updated: startTime)
        return EntryRow(Ledger(entries: [entry]).resolvedEntries()[0], projectTitle: project, flagged: false)
    }

    /// Rows in the model's order: by start.
    var rows: [EntryRow] {
        [
            row("Kickoff", project: "acme › Website", from: "09:00", to: "10:00"),
            row("Review", project: "Globex › Brand", from: "10:30", to: "12:00"),
            row("Email", project: "Admin", from: "13:00", to: nil),
        ]
    }

    @Test func theNewestComeFirstAsTheTableOpens() {
        #expect(EntryOrder.sort(rows, by: [EntryOrder(column: .start, order: .reverse)]).map(\.note) == ["Email", "Review", "Kickoff"])
        #expect(EntryOrder.sort(rows, by: [EntryOrder(column: .start)]).map(\.note) == ["Kickoff", "Review", "Email"])
    }

    @Test func projectsSortIgnoringCase() {
        #expect(EntryOrder.sort(rows, by: [EntryOrder(column: .project)]).map(\.projectTitle) == ["acme › Website", "Admin", "Globex › Brand"])
    }

    @Test func theRunningTimerEndsLast() {
        #expect(EntryOrder.sort(rows, by: [EntryOrder(column: .end)]).map(\.note) == ["Kickoff", "Review", "Email"])
        #expect(EntryOrder.sort(rows, by: [EntryOrder(column: .end, order: .reverse)]).first?.note == "Email")
    }
}
#endif

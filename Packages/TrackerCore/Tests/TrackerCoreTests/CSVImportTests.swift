import Foundation
import Testing
@testable import TrackerCore

@Suite struct CSVImportTests {
    let now = t("2026-09-27T12:00:00+02:00")
    let berlin = "Europe/Berlin"

    func plan(_ text: String, into ledger: Ledger = Ledger()) throws -> CSVImport.Plan {
        try CSVImport.plan(Data(text.utf8), into: ledger, timeZone: berlin, now: now)
    }

    /// The imported entries' projects, as "Client › Project".
    func titles(_ plan: CSVImport.Plan, into ledger: Ledger = Ledger()) -> [String] {
        var ledger = ledger
        ledger.add(plan, now: now)
        return plan.entries.map { ledger.projectTitle($0.projectID) }
    }

    @Test func readsItsOwnExportBack() throws {
        var original = Ledger(
            clients: [Client(id: uuid(20), name: "Acme, Inc.", updated: now)],
            projects: [
                Project(id: uuid(10), clientID: uuid(20), name: "Website", updated: now),
                Project(id: uuid(11), name: "Internal", updated: now),
            ]
        )
        original.merge(TimeEntry(
            projectID: uuid(10), start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T11:25:00+02:00"),
            timeZone: berlin, tags: ["design", "call"], note: "Kickoff, \"round 2\"\nwith notes", updated: now
        ))
        original.merge(TimeEntry(
            projectID: uuid(11), start: t("2026-09-24T13:00:00+02:00"), end: t("2026-09-24T13:10:00+02:00"),
            timeZone: berlin, updated: now
        ))
        original.merge(TimeEntry(
            start: t("2026-09-24T22:00:00-04:00"), end: t("2026-09-24T23:00:00-04:00"),
            timeZone: "America/New_York", note: "Unassigned", updated: now
        ))
        let range = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
        let csv = CSVExport.text(for: Report(ReportRequest(range: range), ledger: original).entries, ledger: original)

        let result = try plan(csv)
        #expect(result.problems.isEmpty)
        #expect(result.alreadyThere == 0)
        #expect(result.clients.map(\.name) == ["Acme, Inc."])
        #expect(result.projects.map(\.name) == ["Website", "Internal"])
        #expect(titles(result) == ["Acme, Inc. › Website", "Internal", "Unassigned"])
        #expect(result.entries.map(\.start) == [
            t("2026-09-23T09:00:00+02:00"), t("2026-09-24T13:00:00+02:00"), t("2026-09-24T22:00:00-04:00"),
        ])
        #expect(result.entries.compactMap(\.end) == [
            t("2026-09-23T11:25:00+02:00"), t("2026-09-24T13:10:00+02:00"), t("2026-09-24T23:00:00-04:00"),
        ])
        #expect(result.entries[0].tags == ["design", "call"])
        #expect(result.entries[0].note == "Kickoff, \"round 2\"\nwith notes")
        #expect(result.entries[0].timeZone == berlin)
        // New York's offset isn't Berlin's, so that entry keeps its offset.
        let newYork = result.entries[2]
        #expect(Zones.offset(newYork.timeZone, at: newYork.start) == -4 * 3600, "\(newYork.timeZone)")
        #expect(newYork.day == LocalDate(year: 2026, month: 9, day: 24))
        #expect(result.days == LocalDate(year: 2026, month: 9, day: 23)...LocalDate(year: 2026, month: 9, day: 24))

        // Importing it again adds nothing.
        var imported = Ledger()
        imported.add(result, now: now)
        let again = try plan(csv, into: imported)
        #expect(again.entries.isEmpty)
        #expect(again.clients.isEmpty)
        #expect(again.projects.isEmpty)
        #expect(again.alreadyThere == 3)
    }

    @Test func readsSeparateDatesAndTimes() throws {
        // As Toggl Track exports them.
        let result = try plan("""
        User,Email,Client,Project,Task,Description,Billable,Start date,Start time,End date,End time,Duration,Tags,Amount ()
        Jo,jo@example.com,Acme,Website,,Wireframes,No,2026-09-23,09:00:00,2026-09-23,10:30:00,01:30:00,"design, call",
        Jo,jo@example.com,,,,Night shift,No,2026-09-23,23:00:00,2026-09-24,01:00:00,02:00:00,,
        """)
        #expect(result.problems.isEmpty)
        #expect(titles(result) == ["Acme › Website", "Unassigned"])
        #expect(result.entries.map(\.start) == [t("2026-09-23T09:00:00+02:00"), t("2026-09-23T23:00:00+02:00")])
        #expect(result.entries.compactMap(\.end) == [t("2026-09-23T10:30:00+02:00"), t("2026-09-24T01:00:00+02:00")])
        #expect(result.entries[0].tags == ["design", "call"])
        #expect(result.entries[0].note == "Wireframes")
    }

    @Test func readsCompactDateTimes() throws {
        // In UTC, as Timewarrior writes them, without seconds or zone, and
        // with an offset.
        let result = try plan("""
        start,end,tags
        20260713T152036Z,20260713T163000Z,design
        20260714T0900,20260714T1015,
        20260715T090000+0400,20260715T100000+04:00,
        """)
        #expect(result.problems.isEmpty)
        #expect(result.entries.map(\.start) == [
            t("2026-07-13T15:20:36Z"), t("2026-07-14T09:00:00+02:00"), t("2026-07-15T09:00:00+04:00"),
        ])
        #expect(result.entries.compactMap(\.end) == [
            t("2026-07-13T16:30:00Z"), t("2026-07-14T10:15:00+02:00"), t("2026-07-15T10:00:00+04:00"),
        ])
        // UTC doesn't say where the work was done, so it shows at Berlin's
        // time, 17:20; an offset keeps the time of day it was recorded at.
        #expect(result.entries[0].timeZone == berlin)
        #expect(result.entries[1].timeZone == berlin)
        let dubai = result.entries[2]
        #expect(Zones.offset(dubai.timeZone, at: dubai.start) == 4 * 3600)
    }

    @Test func showsTimesInUTCInThisDevicesZone() throws {
        let result = try plan("""
        date,start,end
        ,2026-07-13T15:20:36Z,2026-07-13T16:30:00Z
        20260714,09:00,10:00
        """)
        #expect(result.problems.isEmpty)
        #expect(result.entries.map(\.timeZone) == [berlin, berlin])
        #expect(result.entries.map(\.start) == [t("2026-07-13T15:20:36Z"), t("2026-07-14T09:00:00+02:00")])
    }

    @Test func readsAmericanDatesAndTwelveHourTimes() throws {
        // As Clockify exports them.
        let result = try plan("""
        Project,Client,Description,Task,User,Group,Email,Tags,Billable,Start Date,Start Time,End Date,End Time,Duration (h),Duration (decimal)
        Website,Acme,Review,,Jo,,jo@example.com,,Yes,09/23/2026,01:00:00 PM,09/23/2026,02:15:00 PM,01:15:00,1.25
        """)
        #expect(result.problems.isEmpty)
        #expect(result.entries.map(\.start) == [t("2026-09-23T13:00:00+02:00")])
        #expect(result.entries.compactMap(\.end) == [t("2026-09-23T14:15:00+02:00")])
    }

    @Test func readsSemicolonsAndDaysFirst() throws {
        let result = try plan("""
        date;start;end;project;note
        23.09.2026;9:00;17:30;Internal;Planung
        24/09/2026;22:00;1:00;Internal;Release
        """)
        #expect(result.problems.isEmpty)
        #expect(result.entries.map(\.start) == [t("2026-09-23T09:00:00+02:00"), t("2026-09-24T22:00:00+02:00")])
        // An end earlier than the start is on the next day.
        #expect(result.entries.compactMap(\.end) == [t("2026-09-23T17:30:00+02:00"), t("2026-09-25T01:00:00+02:00")])
        #expect(result.projects.map(\.name) == ["Internal"])
    }

    @Test func placesRowsWithoutTimesOneAfterAnother() throws {
        // As Harvest exports them: a day and hours.
        let result = try plan("""
        Date,Client,Project,Task,Notes,Hours
        2026-09-23,Acme,Website,Design,Mockups,1.5
        2026-09-23,,Internal,Admin,Invoices,"0,5"
        2026-09-24,,Internal,Admin,Invoices,0.25
        """)
        #expect(result.problems.isEmpty)
        #expect(result.placed == 3)
        #expect(result.entries.map(\.start) == [
            t("2026-09-23T09:00:00+02:00"), t("2026-09-23T10:30:00+02:00"), t("2026-09-24T09:00:00+02:00"),
        ])
        #expect(result.entries.compactMap(\.end) == [
            t("2026-09-23T10:30:00+02:00"), t("2026-09-23T11:00:00+02:00"), t("2026-09-24T09:15:00+02:00"),
        ])
    }

    @Test func usesExistingClientsProjectsAndTags() throws {
        let ledger = Ledger(
            clients: [Client(id: uuid(20), name: "Acme", updated: now)],
            projects: [Project(id: uuid(10), clientID: uuid(20), name: "Website", archived: true, updated: now)],
            entries: [TimeEntry(start: t("2026-09-01T09:00:00+02:00"), end: t("2026-09-01T10:00:00+02:00"), timeZone: berlin, tags: ["Design"], updated: now)]
        )
        let result = try plan("""
        start,end,client,project,tags
        2026-09-23 09:00,2026-09-23 10:00,ACME,website,design;new
        """, into: ledger)
        #expect(result.clients.isEmpty)
        #expect(result.projects.isEmpty)
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.projectID == uuid(10))
        #expect(result.entries.map(\.tags) == [["Design", "new"]])
    }

    @Test func givesNewProjectsThePalettesNextColors() throws {
        let ledger = Ledger(projects: [Project(id: uuid(10), name: "Website", color: Palette.colors[0], updated: now)])
        let result = try plan("""
        date,start,end,project
        2026-09-23,09:00,10:00,Website
        2026-09-23,10:00,11:00,Internal
        2026-09-23,11:00,12:00,Research
        """, into: ledger)
        #expect(result.projects.map(\.name) == ["Internal", "Research"])
        // Each one its own, after the colors the ledger's projects have.
        #expect(result.projects.map(\.color) == [Palette.colors[1], Palette.colors[2]])
    }

    @Test func reportsRowsItCantRead() throws {
        let result = try plan("""
        date,start,end,duration,note
        2026-09-23,banana,10:00,,Fruit
        2026-09-23,09:00,,,No end

        2026-09-31,09:00,10:00,,No such day
        2026-09-23,10:00,09:00:00 PM,,Fine
        2026-09-23,11:00,,1:5,Bad duration
        """)
        #expect(result.entries.map(\.note) == ["Fine"])
        #expect(result.problems.map(\.line) == [2, 3, 5, 7])
        #expect(result.problems.first?.message == "Can't read the start \u{201C}banana\u{201D}.")
    }

    @Test func refusesFilesWithoutRowsOrStarts() {
        #expect(throws: CSVImport.Failure.noRows) {
            try plan("date,start,end\n")
        }
        #expect(throws: CSVImport.Failure.noStartColumn) {
            try plan("project,note\nWebsite,Mockups\n")
        }
    }

    @Test func readsQuotedFieldsAndLineBreaks() {
        let records = CSVImport.records("a,\"b,c\",\"d\"\"e\"\r\n\"line\nbreak\",,x\n", separator: ",")
        #expect(records.map { $0.fields } == [["a", "b,c", "d\"e"], ["line\nbreak", "", "x"]])
        #expect(records.map { $0.line } == [1, 2])
        #expect(CSVImport.separator(in: "a;b;\"c,d,e\"\n1,2,3") == ";")
        #expect(CSVImport.decode(Data([0xEF, 0xBB, 0xBF] + Array("date".utf8))) == "date")
    }

    @Test func readsCompactISO8601() {
        #expect(CSVImport.extended("20260713T152036Z") == "2026-07-13T15:20:36Z")
        #expect(CSVImport.extended("20260713t1520z") == "2026-07-13T15:20:00Z")
        #expect(CSVImport.extended("20260713T152036.25+0200") == "2026-07-13T15:20:36+02:00")
        #expect(CSVImport.extended("20260713 152036-05") == "2026-07-13T15:20:36-05:00")
        #expect(CSVImport.extended("20260713T152036+02:30") == "2026-07-13T15:20:36+02:30")
        #expect(CSVImport.extended("20260713T152036") == "2026-07-13T15:20:36")
        #expect(CSVImport.extended("20260713") == "2026-07-13")
        // Anything else stays as it is.
        for text in ["2026-07-13T15:20:36Z", "09:00", "1.5", "20260713T15", "20260713T152036+2", "20260713T152036Zx", "Design"] {
            #expect(CSVImport.extended(text) == text)
        }
    }

    @Test func readsDatesTimesAndDurations() {
        #expect(CSVImport.date("2026-09-23", dayFirst: false) == LocalDate(year: 2026, month: 9, day: 23))
        #expect(CSVImport.date("09/23/26", dayFirst: false) == LocalDate(year: 2026, month: 9, day: 23))
        #expect(CSVImport.date("09/10/2026", dayFirst: true) == LocalDate(year: 2026, month: 10, day: 9))
        #expect(CSVImport.date("2026-02-30", dayFirst: false) == nil)
        #expect(CSVImport.clockTime("9:05") == 9 * 3600 + 5 * 60)
        #expect(CSVImport.clockTime("12:00:00 AM") == 0)
        #expect(CSVImport.clockTime("25:00") == nil)
        let minute: Int64 = 60000
        #expect(CSVImport.duration("1:30") == 90 * minute)
        #expect(CSVImport.duration("01:30:30") == 90 * minute + minute / 2)
        #expect(CSVImport.duration("1,25") == 75 * minute)
        #expect(CSVImport.duration("1:5") == nil)
        #expect(CSVImport.duration("1h") == nil)
    }
}

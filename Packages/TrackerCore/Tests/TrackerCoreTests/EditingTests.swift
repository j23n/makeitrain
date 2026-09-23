import Foundation
import Testing
@testable import TrackerCore

@Suite struct EditingTests {
    let morning = t("2026-09-23T09:00:00+02:00")
    let noon = t("2026-09-23T12:00:00+02:00")

    func entry(_ number: Int, project: UUID? = nil, tags: [String] = [], note: String = "") -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            projectID: project,
            start: t("2026-09-23T09:00:00+02:00"),
            end: t("2026-09-23T10:00:00+02:00"),
            timeZone: "Europe/Berlin",
            tags: tags,
            note: note,
            updated: t("2026-09-23T10:00:00+02:00")
        )
    }

    @Test func addingStampsTheEntryAndCleansItUp() {
        var ledger = Ledger()
        var new = entry(1, tags: [" design ", "Design", "a;b"])
        new.start = t("2026-09-23T09:00:00.600+02:00")
        let changes = ledger.addEntry(new, now: noon)
        let added = ledger.entries[uuid(1)]
        #expect(added?.start == morning)
        #expect(added?.tags == ["design", "ab"])
        #expect(added?.updated == noon)
        #expect(added?.endUpdated == noon)
        #expect(changes == Changes(months: [MonthKey(year: 2026, month: 9)]))
    }

    @Test func deletingKeepsARecordWithoutTheText() {
        var ledger = Ledger()
        ledger.addEntry(entry(1, tags: ["client"], note: "Call about the secret merger"), now: morning)
        let before = ledger.entries[uuid(1)]!
        ledger.deleteEntry(uuid(1), now: noon)
        let deleted = ledger.entries[uuid(1)]!
        #expect(deleted.isDeleted)
        #expect(deleted.note == "")
        #expect(deleted.tags == [])
        #expect(deleted.updated > before.updated)
        #expect(ledger.resolvedEntries().isEmpty)

        // Undo puts the old copy back, stamped as a new change.
        ledger.updateEntry(uuid(1), now: noon.adding(seconds: 1)) { $0 = before }
        let restored = ledger.entries[uuid(1)]!
        #expect(!restored.isDeleted)
        #expect(restored.note == "Call about the secret merger")
        #expect(restored.updated > deleted.updated)
    }

    @Test func projectsWithEntriesCantBeDeleted() throws {
        let project = Project(id: uuid(10), name: "Website", updated: morning)
        var ledger = Ledger(projects: [project], entries: [entry(1, project: uuid(10))])
        #expect(throws: LedgerError.hasEntries) {
            var copy = ledger
            try copy.deleteProject(uuid(10), now: noon)
        }
        ledger.updateProject(uuid(10), now: noon) { $0.archived = true }
        #expect(ledger.projects[uuid(10)]?.archived == true)

        // Once its entries are gone, it can go too.
        ledger.deleteEntry(uuid(1), now: noon)
        try ledger.deleteProject(uuid(10), now: noon)
        #expect(ledger.projects[uuid(10)]?.isDeleted == true)
        #expect(ledger.projects[uuid(10)]?.name == "Website")
    }

    @Test func deletingAClientDeletesItsProjects() throws {
        let client = Client(id: uuid(20), name: "Acme", updated: morning)
        let project = Project(id: uuid(10), clientID: uuid(20), name: "Website", updated: morning)
        var ledger = Ledger(clients: [client], projects: [project], entries: [entry(1, project: uuid(10))])
        #expect(throws: LedgerError.hasEntries) {
            var copy = ledger
            try copy.deleteClient(uuid(20), now: noon)
        }
        ledger.deleteEntry(uuid(1), now: noon)
        let changes = try ledger.deleteClient(uuid(20), now: noon)
        #expect(ledger.clients[uuid(20)]?.isDeleted == true)
        #expect(ledger.projects[uuid(10)]?.isDeleted == true)
        #expect(changes == Changes(projects: true))
    }

    @Test func mergingAProjectMovesItsEntries() throws {
        let duplicate = Project(id: uuid(10), name: "Acme", updated: morning)
        let original = Project(id: uuid(11), name: "Acme", updated: morning)
        var ledger = Ledger(projects: [duplicate, original], entries: [entry(1, project: uuid(10)), entry(2, project: uuid(11))])
        let changes = try ledger.mergeProject(uuid(10), into: uuid(11), now: noon)
        #expect(ledger.entries[uuid(1)]?.projectID == uuid(11))
        #expect(ledger.projects[uuid(10)]?.isDeleted == true)
        #expect(changes == Changes(months: [MonthKey(year: 2026, month: 9)], projects: true))
    }

    @Test func mergingAClientMovesItsProjects() throws {
        let clients = [Client(id: uuid(20), name: "Acme", updated: morning), Client(id: uuid(21), name: "ACME", updated: morning)]
        let project = Project(id: uuid(10), clientID: uuid(20), name: "Website", updated: morning)
        var ledger = Ledger(clients: clients, projects: [project])
        try ledger.mergeClient(uuid(20), into: uuid(21), now: noon)
        #expect(ledger.projects[uuid(10)]?.clientID == uuid(21))
        #expect(ledger.clients[uuid(20)]?.isDeleted == true)
        #expect(throws: LedgerError.notFound) {
            var copy = ledger
            try copy.mergeClient(uuid(21), into: uuid(21), now: noon)
        }
    }

    @Test func splittingMakesTwoEntriesThatMeet() {
        var ledger = Ledger(entries: [entry(1, project: uuid(10), tags: ["design"], note: "Wireframes")])
        let changes = ledger.split(uuid(1), at: t("2026-09-23T09:20:00.600+02:00"), newID: uuid(2), now: noon)
        let first = ledger.entries[uuid(1)]!
        let second = ledger.entries[uuid(2)]!
        #expect(first.start == morning)
        #expect(first.end == t("2026-09-23T09:20:00+02:00"))
        #expect(first.endUpdated == noon)
        #expect(second.start == first.end)
        #expect(second.end == t("2026-09-23T10:00:00+02:00"))
        #expect(second.projectID == uuid(10))
        #expect(second.tags == ["design"])
        #expect(second.note == "Wireframes")
        #expect(second.timeZone == "Europe/Berlin")
        #expect(second.updated == noon)
        #expect(changes == Changes(months: [MonthKey(year: 2026, month: 9)]))
    }

    @Test func splittingNeedsATimeInsideTheEntry() {
        let original = Ledger(entries: [entry(1)])
        for time in ["2026-09-23T08:00:00+02:00", "2026-09-23T09:00:00+02:00", "2026-09-23T10:00:00+02:00", "2026-09-23T11:00:00+02:00"] {
            var ledger = original
            let changes = ledger.split(uuid(1), at: t(time), newID: uuid(2), now: noon)
            #expect(ledger == original)
            #expect(changes.isEmpty)
        }

        var ledger = original
        ledger.deleteEntry(uuid(1), now: noon)
        let deleted = ledger
        ledger.split(uuid(1), at: t("2026-09-23T09:30:00+02:00"), newID: uuid(2), now: noon)
        #expect(ledger == deleted)
    }

    @Test func splittingTheRunningTimerKeepsTheSecondPartRunning() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), note: "Sync engine", timeZone: "Europe/Berlin", at: morning, now: morning)

        // Not after now: the timer hasn't got there yet.
        var copy = ledger
        copy.split(uuid(1), at: noon.adding(seconds: 60), newID: uuid(2), now: noon)
        #expect(copy == ledger)

        ledger.split(uuid(1), at: t("2026-09-23T11:00:00+02:00"), newID: uuid(2), now: noon)
        #expect(ledger.entries[uuid(1)]?.end == t("2026-09-23T11:00:00+02:00"))
        #expect(ledger.entries[uuid(2)]?.start == t("2026-09-23T11:00:00+02:00"))
        #expect(ledger.entries[uuid(2)]?.note == "Sync engine")
        #expect(ledger.runningEntry?.id == uuid(2))
    }

    @Test func renamingATagRenamesItEverywhere() {
        var ledger = Ledger(entries: [
            entry(1, tags: ["Design"]),
            entry(2, tags: ["design", "call"]),
            entry(3, tags: ["call"]),
        ])
        ledger.renameTag("design", to: "UX", now: noon)
        #expect(ledger.entries[uuid(1)]?.tags == ["UX"])
        #expect(ledger.entries[uuid(2)]?.tags == ["UX", "call"])
        #expect(ledger.entries[uuid(3)]?.tags == ["call"])

        // Renaming to an existing tag merges the two.
        ledger.renameTag("call", to: "ux", now: noon)
        #expect(ledger.entries[uuid(2)]?.tags == ["UX"])
        #expect(ledger.entries[uuid(3)]?.tags == ["ux"])
    }

    @Test func cleansUpTags() {
        #expect(Tags.normalize(["  design ", "Design", "client;call", "", " ", "a \n b"]) == ["design", "clientcall", "a b"])
        #expect(Tags.same("Design", "dESIGN"))
    }
}

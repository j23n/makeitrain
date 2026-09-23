import Foundation
import Testing
@testable import TrackerCore

@Suite struct MergeTests {
    let id = uuid(1)

    func entry(note: String = "", updated: String) -> TimeEntry {
        TimeEntry(id: id, start: t("2026-09-23T09:00:00+02:00"), timeZone: "Europe/Berlin", note: note, updated: t(updated))
    }

    @Test func theNewestUpdateWins() {
        let older = entry(note: "old", updated: "2026-09-23T10:00:00Z")
        let newer = entry(note: "new", updated: "2026-09-23T10:00:00.001Z")
        #expect(older.merged(with: newer).note == "new")
        #expect(newer.merged(with: older).note == "new")
    }

    @Test func aStopSurvivesAnEditToAnOutOfDateCopy() {
        let running = entry(note: "Draft", updated: "2026-09-23T09:00:00+02:00")
        // Mac B stops the timer at 12:00.
        var macB = Ledger(entries: [running])
        macB.stopTimer(at: t("2026-09-23T12:00:00+02:00"), now: t("2026-09-23T12:00:00+02:00"))
        // Mac A hasn't synced yet and edits the running timer's note at 12:05.
        var macA = Ledger(entries: [running])
        macA.updateEntry(id, now: t("2026-09-23T12:05:00+02:00")) { $0.note = "Draft v2" }

        for merged in [macA.merging(macB), macB.merging(macA)] {
            #expect(merged.entries[id]?.note == "Draft v2")
            #expect(merged.entries[id]?.end == t("2026-09-23T12:00:00+02:00"))
            #expect(merged.runningEntry == nil)
        }
    }

    @Test func theLatestEndWins() {
        var early = entry(updated: "2026-09-23T10:00:00Z")
        early.end = t("2026-09-23T10:00:00+02:00")
        early.endUpdated = t("2026-09-23T10:00:00+02:00")
        var corrected = early
        corrected.end = t("2026-09-23T09:45:00+02:00")
        corrected.endUpdated = t("2026-09-23T11:00:00+02:00")
        #expect(early.merged(with: corrected).end == t("2026-09-23T09:45:00+02:00"))
        #expect(corrected.merged(with: early).end == t("2026-09-23T09:45:00+02:00"))
    }

    @Test func tiesBreakTheSameWayEverywhere() {
        let a = entry(note: "a", updated: "2026-09-23T10:00:00Z")
        let b = entry(note: "b", updated: "2026-09-23T10:00:00Z")
        #expect(a.merged(with: b) == b.merged(with: a))
        #expect(a.merged(with: b).note == "b")

        // Different bytes for the same text in Unicode's eyes still differ.
        let composed = entry(note: "\u{E9}", updated: "2026-09-23T10:00:00Z")
        let decomposed = entry(note: "e\u{301}", updated: "2026-09-23T10:00:00Z")
        #expect(Array(composed.merged(with: decomposed).note.utf8) == Array(decomposed.merged(with: composed).note.utf8))

        // A copy that isn't deleted wins a tie.
        var deleted = a
        deleted.deleted = a.updated
        #expect(a.merged(with: deleted).deleted == nil)
        #expect(deleted.merged(with: a).deleted == nil)
    }

    @Test func aDeleteBeatsOlderCopies() {
        let alive = entry(note: "x", updated: "2026-09-23T10:00:00Z")
        var deleted = entry(updated: "2026-09-23T11:00:00Z")
        deleted.deleted = t("2026-09-23T11:00:00Z")
        #expect(alive.merged(with: deleted).isDeleted)
        #expect(deleted.merged(with: alive).isDeleted)
    }

    @Test func entryMergesDontDependOnOrder() {
        var rng = SeededGenerator(seed: 11)
        for _ in 0..<3000 {
            let a = randomCopy(using: &rng)
            let b = randomCopy(using: &rng)
            let c = randomCopy(using: &rng)
            #expect(a.merged(with: b) == b.merged(with: a))
            #expect(a.merged(with: b).merged(with: c) == a.merged(with: b.merged(with: c)))
            #expect(a.merged(with: a) == a)
        }
    }

    @Test func clientAndProjectMergesDontDependOnOrder() {
        var rng = SeededGenerator(seed: 12)
        for _ in 0..<3000 {
            let clients = (0..<3).map { _ in
                Client(
                    id: id,
                    name: ["Acme", "ACME", "Beta"].randomElement(using: &rng)!,
                    archived: Bool.random(using: &rng),
                    updated: t("2026-09-23T10:00:00Z").adding(milliseconds: Int64.random(in: 0...2, using: &rng)),
                    deleted: Bool.random(using: &rng) ? t("2026-09-23T10:00:00Z") : nil
                )
            }
            let (a, b, c) = (clients[0], clients[1], clients[2])
            #expect(a.merged(with: b) == b.merged(with: a))
            #expect(a.merged(with: b).merged(with: c) == a.merged(with: b.merged(with: c)))
            #expect(a.merged(with: a) == a)

            let projects = (0..<3).map { _ in
                Project(
                    id: id,
                    clientID: [nil, uuid(7), uuid(8)].randomElement(using: &rng)!,
                    name: ["Web", "App"].randomElement(using: &rng)!,
                    color: ["#000000", "#FFFFFF"].randomElement(using: &rng)!,
                    archived: Bool.random(using: &rng),
                    updated: t("2026-09-23T10:00:00Z").adding(milliseconds: Int64.random(in: 0...2, using: &rng)),
                    deleted: Bool.random(using: &rng) ? t("2026-09-23T10:00:00Z") : nil
                )
            }
            let (p, q, r) = (projects[0], projects[1], projects[2])
            #expect(p.merged(with: q) == q.merged(with: p))
            #expect(p.merged(with: q).merged(with: r) == p.merged(with: q.merged(with: r)))
            #expect(p.merged(with: p) == p)
        }
    }

    @Test func ledgersEndUpTheSameInAnyOrder() {
        var rng = SeededGenerator(seed: 13)
        for _ in 0..<300 {
            let ledgers = (0..<4).map { _ in
                Ledger(entries: (0..<Int.random(in: 0...6, using: &rng)).map { _ in
                    randomCopy(of: uuid(Int.random(in: 1...3, using: &rng)), using: &rng)
                })
            }
            let forwards = ledgers.reduce(Ledger()) { $0.merging($1) }
            let shuffled = ledgers.shuffled(using: &rng).reduce(Ledger()) { $0.merging($1) }
            let twice = (ledgers + ledgers.reversed()).reduce(Ledger()) { $0.merging($1) }
            #expect(forwards == shuffled)
            #expect(forwards == twice)
        }
    }

    /// A random copy of an entry. Values come from small sets so that ties are common.
    private func randomCopy(of id: UUID? = nil, using rng: inout SeededGenerator) -> TimeEntry {
        let base = t("2026-09-23T09:00:00Z")
        let end: Timestamp? = Bool.random(using: &rng) ? base.adding(seconds: Int64.random(in: 1...3, using: &rng) * 3600) : nil
        let updated = base.adding(milliseconds: Int64.random(in: 0...3, using: &rng))
        return TimeEntry(
            id: id ?? self.id,
            projectID: [nil, uuid(7), uuid(8)].randomElement(using: &rng)!,
            start: base.adding(seconds: Int64.random(in: 0...2, using: &rng) * 60),
            end: end,
            endUpdated: base.adding(milliseconds: Int64.random(in: 0...3, using: &rng)),
            timeZone: ["Europe/Berlin", "America/New_York"].randomElement(using: &rng)!,
            tags: [[], ["a"], ["a", "b"], ["b"]].randomElement(using: &rng)!,
            note: ["", "x", "y"].randomElement(using: &rng)!,
            updated: updated,
            deleted: Int.random(in: 0..<4, using: &rng) == 0 ? updated : nil
        )
    }
}

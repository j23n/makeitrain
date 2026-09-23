import Foundation
import Testing
@testable import TrackerCore

/// Several devices edit the same folder with out-of-date data and clocks that
/// disagree, saving and catching up at random. Afterwards they must all end
/// up with the same data, and nothing anyone created may be lost.
@Suite struct SimulationTests {
    struct Device {
        var ledger = Ledger()
        var pending = Changes()
        /// How far this device's clock is off, in milliseconds.
        var skew: Int64

        mutating func record(_ changes: Changes) {
            pending.formUnion(changes)
        }

        mutating func save(to folder: Folder) throws {
            let result = try folder.save(ledger, changes: pending)
            ledger = result.ledger
            pending = result.pending
        }

        mutating func catchUp(from folder: Folder) throws {
            let loaded = try folder.load()
            ledger.merge(loaded.ledger)
            pending.formUnion(loaded.pending)
        }
    }

    @Test(arguments: 1...12)
    func devicesEndUpWithTheSameData(seed: Int) throws {
        var rng = SeededGenerator(seed: UInt64(seed))
        let files = MemoryFiles()
        let folder = Folder(root: URL(fileURLWithPath: "/data"), access: files)
        var devices = (0..<3).map { _ in Device(skew: Int64.random(in: -120_000...120_000, using: &rng)) }
        let zones = ["Europe/Berlin", "America/New_York", "Asia/Tokyo"]
        var clock = t("2026-09-28T08:00:00Z")
        var created: Set<UUID> = []

        for _ in 0..<300 {
            clock = clock.adding(seconds: Int64.random(in: 60...20000, using: &rng))
            let index = Int.random(in: 0..<devices.count, using: &rng)
            let now = clock.adding(milliseconds: devices[index].skew)
            let live = devices[index].ledger.entries.values
                .filter { !$0.isDeleted }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }

            switch Int.random(in: 0..<12, using: &rng) {
            case 0...2:
                let id = randomUUID(using: &rng)
                created.insert(id)
                let zone = zones.randomElement(using: &rng)!
                let changes = devices[index].ledger.startTimer(id: id, note: "timer", timeZone: zone, at: now, now: now)
                devices[index].record(changes)
            case 3:
                let changes = devices[index].ledger.stopTimer(at: now, now: now)
                devices[index].record(changes)
            case 4:
                let id = randomUUID(using: &rng)
                created.insert(id)
                let start = now.adding(seconds: -Int64.random(in: 0...(40 * 86400), using: &rng))
                let entry = TimeEntry(
                    id: id,
                    start: start,
                    end: start.adding(seconds: 3600),
                    timeZone: zones.randomElement(using: &rng)!,
                    note: "by hand",
                    updated: now
                )
                let changes = devices[index].ledger.addEntry(entry, now: now)
                devices[index].record(changes)
            case 5, 6:
                guard let id = live.randomElement(using: &rng) else { break }
                // Sometimes far enough to move the entry to another month.
                let shift = Int64.random(in: -3...3, using: &rng) * 10 * 86400
                let note = "edit \(Int.random(in: 0...9, using: &rng))"
                let changes = devices[index].ledger.updateEntry(id, now: now) { entry in
                    entry.note = note
                    entry.start = entry.start.adding(seconds: shift)
                    entry.end = entry.end?.adding(seconds: shift)
                }
                devices[index].record(changes)
            case 7:
                guard let id = live.randomElement(using: &rng) else { break }
                let changes = devices[index].ledger.deleteEntry(id, now: now)
                devices[index].record(changes)
            case 8, 9:
                try devices[index].save(to: folder)
            default:
                try devices[index].catchUp(from: folder)
            }
        }

        // Everyone saves and catches up twice: the first round can turn up
        // old copies of moved entries, which the second round cleans up.
        for _ in 0..<2 {
            for index in devices.indices {
                try devices[index].save(to: folder)
            }
            for index in devices.indices {
                try devices[index].catchUp(from: folder)
            }
        }

        let settled = try folder.load()
        #expect(settled.issues.isEmpty)
        #expect(settled.pending.isEmpty)
        for device in devices {
            #expect(device.ledger == settled.ledger)
        }
        #expect(created.isSubset(of: Set(settled.ledger.entries.keys)))
        #expect(settled.ledger.resolvedEntries().filter(\.isRunning).count <= 1)

        // The files are settled: saving every month again writes nothing.
        let writes = files.writes
        let everything = Changes(months: Set(settled.ledger.entries.values.map(\.month)), projects: true)
        _ = try folder.save(settled.ledger, changes: everything)
        #expect(files.writes == writes)
    }
}

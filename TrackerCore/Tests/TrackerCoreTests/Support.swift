import Foundation
@testable import TrackerCore

/// A readable fixed id: `uuid(1)` is 00000000-0000-0000-0000-000000000001.
func uuid(_ number: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-" + padded(number, 12))!
}

/// A time written as in the files, such as "2026-09-23T09:15:00+02:00".
func t(_ text: String) -> Timestamp {
    guard let time = DateTimeFormat.parse(text) else {
        fatalError("Not a date-time: \(text)")
    }
    return time
}

/// SplitMix64, so that random tests repeat exactly.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func randomUUID(using rng: inout SeededGenerator) -> UUID {
    let hex = (0..<2).map { _ -> String in
        let digits = String(rng.next(), radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }.joined()
    let c = Array(hex)
    return UUID(uuidString: "\(String(c[0..<8]))-\(String(c[8..<12]))-\(String(c[12..<16]))-\(String(c[16..<20]))-\(String(c[20..<32]))")!
}

/// Files in memory, standing in for a disk. It counts writes and can fail a
/// write on purpose, standing in for a crash.
final class MemoryFiles: FileAccess, @unchecked Sendable {
    struct Crash: Error {}

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var writeCount = 0
    private var budget: Int?

    /// Writes so far.
    var writes: Int {
        locked { writeCount }
    }

    /// How many more writes succeed before one fails, or nil for no limit.
    var writeBudget: Int? {
        get { locked { budget } }
        set { locked { budget = newValue } }
    }

    func put(_ path: String, _ data: Data) {
        locked { files[path] = data }
    }

    func contents(_ path: String) -> Data? {
        locked { files[path] }
    }

    /// Every file's full path, sorted.
    func paths() -> [String] {
        locked { files.keys.sorted() }
    }

    func snapshot() -> [String: Data] {
        locked { files }
    }

    func fileNames(in folder: URL) throws -> [String] {
        let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        return locked {
            files.keys.compactMap { path -> String? in
                guard path.hasPrefix(prefix) else { return nil }
                let name = String(path.dropFirst(prefix.count))
                return name.contains("/") ? nil : name
            }
        }
    }

    func read(_ file: URL) throws -> Data? {
        locked { files[file.path] }
    }

    func write(_ data: Data, to file: URL) throws {
        try locked {
            if let remaining = budget {
                guard remaining > 0 else { throw Crash() }
                budget = remaining - 1
            }
            writeCount += 1
            files[file.path] = data
        }
    }

    func remove(_ file: URL) throws {
        locked { files[file.path] = nil }
    }

    func coordinateReading<T>(_ file: URL, _ body: () throws -> T) throws -> T {
        try body()
    }

    func coordinateWriting<T>(_ files: [URL], _ body: () throws -> T) throws -> T {
        try body()
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

import Foundation

// Merging combines copies of the same record from different devices or files.
// Each merge picks, for each group of fields, the copy with the newest stamp,
// and breaks ties by comparing field values. Because every step is "take the
// larger of two values in a fixed order", merging gives the same result in any
// order and however often it's repeated, so every device ends up with the same
// data.

extension TimeEntry {
    /// Combines two copies of the same entry.
    ///
    /// Everything except `end` comes from the copy with the newest `updated`.
    /// `end` comes from the copy with the newest `endUpdated`, so a stop made
    /// on one device survives an edit made to an out-of-date copy elsewhere.
    public func merged(with other: TimeEntry) -> TimeEntry {
        precondition(id == other.id, "Merging copies of different entries")
        var result = TimeEntry.compareExceptEnd(self, other) >= 0 ? self : other
        let end = [endVersion, other.endVersion].compactMap { $0 }.max()
        result.end = end?.end
        result.endUpdated = end?.stamp
        return result
    }

    /// Orders two copies by everything except `end`: `updated` first, then,
    /// for a tie, field by field. A copy that isn't deleted wins a tie.
    static func compareExceptEnd(_ a: TimeEntry, _ b: TimeEntry) -> Int {
        Order.first([
            Order.compare(a.updated, b.updated),
            Order.compareFlags(a.deleted == nil, b.deleted == nil),
            Order.compareOptional(a.deleted, b.deleted),
            Order.compare(a.start, b.start),
            Order.compareIDs(a.projectID, b.projectID),
            Order.compareText(a.timeZone, b.timeZone),
            Order.compareText(a.note, b.note),
            Order.compareTexts(a.tags, b.tags),
        ])
    }

    /// Whether two copies agree on everything except `end` and the stamps.
    static func sameExceptEnd(_ a: TimeEntry, _ b: TimeEntry) -> Bool {
        a.projectID == b.projectID && a.start == b.start && a.timeZone == b.timeZone
            && a.tags == b.tags && a.note == b.note && a.deleted == b.deleted
    }

    /// `end` with the stamp it merges on, or nil for an entry that never stopped.
    private var endVersion: EndVersion? {
        end.map { EndVersion(stamp: endUpdated ?? updated, end: $0) }
    }
}

private struct EndVersion: Comparable {
    var stamp: Timestamp
    var end: Timestamp

    static func < (lhs: EndVersion, rhs: EndVersion) -> Bool {
        (lhs.stamp, lhs.end) < (rhs.stamp, rhs.end)
    }
}

extension Client {
    /// Combines two copies of the same client: the newest `updated` wins.
    public func merged(with other: Client) -> Client {
        precondition(id == other.id, "Merging copies of different clients")
        let order = Order.first([
            Order.compare(updated, other.updated),
            Order.compareFlags(deleted == nil, other.deleted == nil),
            Order.compareOptional(deleted, other.deleted),
            Order.compareText(name, other.name),
            Order.compareFlags(archived, other.archived),
        ])
        return order >= 0 ? self : other
    }
}

extension Project {
    /// Combines two copies of the same project: the newest `updated` wins.
    public func merged(with other: Project) -> Project {
        precondition(id == other.id, "Merging copies of different projects")
        let order = Order.first([
            Order.compare(updated, other.updated),
            Order.compareFlags(deleted == nil, other.deleted == nil),
            Order.compareOptional(deleted, other.deleted),
            Order.compareText(name, other.name),
            Order.compareIDs(clientID, other.clientID),
            Order.compareText(color, other.color),
            Order.compareFlags(archived, other.archived),
        ])
        return order >= 0 ? self : other
    }
}

/// Three-way comparisons for breaking ties: -1, 0 or 1.
///
/// Text compares by its UTF-8 bytes rather than by Unicode rules, so two
/// different spellings never count as equal and every device agrees.
enum Order {
    /// The first comparison that isn't a tie.
    static func first(_ comparisons: [Int]) -> Int {
        comparisons.first { $0 != 0 } ?? 0
    }

    static func compare<Value: Comparable>(_ a: Value, _ b: Value) -> Int {
        a < b ? -1 : b < a ? 1 : 0
    }

    /// false comes first.
    static func compareFlags(_ a: Bool, _ b: Bool) -> Int {
        compare(a ? 1 : 0, b ? 1 : 0)
    }

    /// nil comes first.
    static func compareOptional(_ a: Timestamp?, _ b: Timestamp?) -> Int {
        switch (a, b) {
        case (nil, nil): 0
        case (nil, _): -1
        case (_, nil): 1
        case let (a?, b?): compare(a, b)
        }
    }

    /// nil comes first.
    static func compareIDs(_ a: UUID?, _ b: UUID?) -> Int {
        compareText(a?.uuidString ?? "", b?.uuidString ?? "")
    }

    static func compareText(_ a: String, _ b: String) -> Int {
        if a.utf8.elementsEqual(b.utf8) { return 0 }
        return a.utf8.lexicographicallyPrecedes(b.utf8) ? -1 : 1
    }

    static func compareTexts(_ a: [String], _ b: [String]) -> Int {
        for (x, y) in zip(a, b) {
            let order = compareText(x, y)
            if order != 0 { return order }
        }
        return compare(a.count, b.count)
    }
}

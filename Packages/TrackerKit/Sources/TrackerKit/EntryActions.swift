import Foundation
import TrackerCore

// What the Mac's and the iPad's context menus and entry editors offer.

/// What a context menu offers for some entries.
public enum EntryMenuItems {
    /// A tag that refers to an issue or pull request, and its address.
    public struct Issue: Hashable, Sendable {
        public let tag: String
        public let url: URL
    }

    /// The tags of the entries' projects, once each, ignoring case: the
    /// tags to offer for adding. `tags` has each project's, as
    /// `AppModel.projectTags` keeps them.
    public static func projectTags(of entries: [ResolvedEntry], in tags: [UUID?: [String]]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for projectID in Set(entries.map(\.entry.projectID)) {
            for tag in tags[projectID] ?? [] where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted(by: Tags.order)
    }

    /// The issues and pull requests the entries' tags refer to, once each,
    /// at most ten.
    public static func issues(of entries: [ResolvedEntry], in ledger: Ledger) -> [Issue] {
        var seen: Set<URL> = []
        var result: [Issue] = []
        for entry in entries {
            for tag in entry.entry.tags {
                if let url = ledger.issueURL(forTag: tag, projectID: entry.entry.projectID), seen.insert(url).inserted {
                    result.append(Issue(tag: tag, url: url))
                }
            }
        }
        return Array(result.sorted { Tags.order($0.tag, $1.tag) }.prefix(10))
    }

    /// The tags on any of the entries, once each, ignoring case.
    public static func tags(in entries: [ResolvedEntry]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries {
            for tag in entry.entry.tags where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Tags typed with commas between them, spelled like the tags the
    /// entries' projects have where they're the same but for case.
    public static func newTags(_ text: String, for entries: [ResolvedEntry], in tags: [UUID?: [String]]) -> [String] {
        let typed = Tags.normalize(text.split(separator: ",").map(String.init))
        let known = projectTags(of: entries, in: tags)
        return typed.map { tag in known.first { Tags.same($0, tag) } ?? tag }
    }
}

/// When an entry can be split.
public enum EntrySplit {
    /// The times an entry can be split at: at least a minute after its
    /// start and before its end, or before now while it runs. Nil when it's
    /// too short to split.
    public static func range(of entry: ResolvedEntry, now: Timestamp) -> ClosedRange<Date>? {
        let first = entry.start.adding(seconds: 60)
        let last = (entry.end ?? now).adding(seconds: -60)
        guard first <= last else { return nil }
        return first.date...last.date
    }

    /// The middle of the entry, on a multiple of five minutes if there's
    /// one inside it.
    public static func suggestedTime(for entry: ResolvedEntry, now: Timestamp) -> Date {
        guard let range = range(of: entry, now: now) else { return entry.start.date }
        let middle = entry.start.adding(milliseconds: entry.start.distance(to: entry.end ?? now) / 2)
        let fiveMinutes: Int64 = 300_000
        let snapped = Timestamp(milliseconds: (middle.milliseconds + fiveMinutes / 2) / fiveMinutes * fiveMinutes)
        if range.contains(snapped.date) {
            return snapped.date
        }
        let minute = Timestamp(milliseconds: (middle.milliseconds + 30000) / 60000 * 60000)
        return min(max(minute.date, range.lowerBound), range.upperBound)
    }
}

extension AppModel {
    /// What an overlap is with, seen from one of its entries, such as
    /// "0:30 overlap with Globex › Brand refresh at 15:30".
    public func overlapDescription(_ overlap: Overlap, from id: UUID) -> String {
        let otherID = overlap.earlier == id ? overlap.later : overlap.earlier
        let other = resolved.first { $0.id == otherID }.map {
            "\(ledger.projectTitle($0.entry.projectID)) at \(Format.time($0.start, zone: $0.entry.timeZone))"
        }
        return "\(Format.duration(overlap.duration)) overlap with \(other ?? "another entry")"
    }
}

extension OverlapFix {
    /// The fix, as a button names it.
    public var title: String {
        switch self {
        case .trimEarlier: "Trim Earlier Entry"
        case .trimLater: "Start Later Entry Later"
        case .split: "Split Entry Around It"
        }
    }
}

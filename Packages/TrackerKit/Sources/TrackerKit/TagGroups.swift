import SwiftUI
import TrackerCore

// Each project's tags, for the Tags screens on the Mac and the iPad.

/// A tag of one project, or of the unassigned entries.
public struct TagKey: Hashable, Sendable {
    public var projectID: UUID?
    /// The tag, lowercased.
    public var tag: String

    public init(projectID: UUID?, tag: String) {
        self.projectID = projectID
        self.tag = tag
    }
}

/// A project's tag with how many of its entries have it and their time.
public struct TagRow: Identifiable, Hashable, Sendable {
    public var projectID: UUID?
    public var tag: String
    public var count: Int
    public var milliseconds: Int64

    public var id: TagKey { TagKey(projectID: projectID, tag: tag.lowercased()) }
}

/// A project and its tags.
public struct TagGroup: Identifiable, Sendable {
    public var projectID: UUID?
    public var rows: [TagRow]

    public var id: String { projectID?.uuidString ?? "" }

    /// Every project with tags, by title, and the unassigned entries' tags
    /// last.
    public static func groups(ledger: Ledger, resolved: [ResolvedEntry], now: Timestamp) -> [TagGroup] {
        var count: [TagKey: Int] = [:]
        var time: [TagKey: Int64] = [:]
        for entry in resolved {
            for tag in Set(entry.entry.tags.map { $0.lowercased() }) {
                let key = TagKey(projectID: entry.entry.projectID, tag: tag)
                count[key, default: 0] += 1
                time[key, default: 0] += entry.duration(now: now)
            }
        }
        return ledger.tagsByProject()
            .map { projectID, tags in
                TagGroup(projectID: projectID, rows: tags.map { tag in
                    let key = TagKey(projectID: projectID, tag: tag.lowercased())
                    return TagRow(projectID: projectID, tag: tag, count: count[key] ?? 0, milliseconds: time[key] ?? 0)
                })
            }
            .sorted { a, b in
                guard let first = a.projectID else { return false }
                guard let second = b.projectID else { return true }
                let (titleA, titleB) = (ledger.projectTitle(first).lowercased(), ledger.projectTitle(second).lowercased())
                return titleA != titleB ? titleA < titleB : first.uuidString < second.uuidString
            }
    }
}

/// A tag with its entries and time, and a link icon when it refers to an
/// issue.
public struct TagRowView: View {
    let row: TagRow
    let linked: Bool

    public init(row: TagRow, linked: Bool) {
        self.row = row
        self.linked = linked
    }

    public var body: some View {
        HStack {
            Label(row.tag, systemImage: linked ? "link" : "tag")
            Spacer()
            Text(row.count == 1 ? "1 entry" : "\(row.count) entries")
                .foregroundStyle(.secondary)
            Text(Format.duration(row.milliseconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 50, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

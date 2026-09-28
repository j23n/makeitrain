import SwiftUI
import TrackerCore

// Small views shared by the Mac and iOS screens.

/// A project's color and title, such as "● Acme › Website".
public struct ProjectLabel: View {
    let ledger: Ledger
    let projectID: UUID?

    public init(ledger: Ledger, projectID: UUID?) {
        self.ledger = ledger
        self.projectID = projectID
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ledger.color(ofProject: projectID))
                .frame(width: 8, height: 8)
            Text(ledger.projectTitle(projectID))
                .lineLimit(1)
                .foregroundStyle(projectID == nil ? .secondary : .primary)
        }
    }
}

/// Tags as small capsules. Tags that refer to a GitHub issue or pull
/// request are tinted and open it when clicked, unless the list isn't
/// interactive, as on the timeline, where clicks select and drag.
public struct TagList: View {
    let tags: [String]
    let links: [String: URL]
    let interactive: Bool
    let wraps: Bool

    /// `links` has the web address of each tag that refers to an issue, as
    /// `Ledger.issueLinks(tags:projectID:)` gives them. A list that `wraps`
    /// breaks into lines instead of staying on one.
    public init(tags: [String], links: [String: URL] = [:], interactive: Bool = true, wraps: Bool = false) {
        self.tags = tags
        self.links = links
        self.interactive = interactive
        self.wraps = wraps
    }

    public var body: some View {
        if wraps {
            FlowLayout(spacing: 4) {
                capsules
            }
        } else {
            HStack(spacing: 4) {
                capsules
            }
        }
    }

    private var capsules: some View {
        ForEach(tags, id: \.self) { tag in
            if let url = links[tag], interactive {
                Link(destination: url) {
                    TagCapsule(tag: tag, linked: true)
                }
                .buttonStyle(.plain)
                .help("Open \(tag) on GitHub")
            } else {
                TagCapsule(tag: tag, linked: links[tag] != nil)
            }
        }
    }
}

/// One tag, in a capsule. A tag linked to an issue is tinted.
struct TagCapsule: View {
    let tag: String
    let linked: Bool

    var body: some View {
        Text(tag)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(linked ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(linked ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.quaternary)))
    }
}

/// Lays its views out in rows, starting a new row when one is full.
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

/// A text field that edits a draft and commits it on Return or when focus
/// leaves, so typing doesn't make an undo step per keystroke. Until the
/// draft is edited, it shows the current value.
public struct CommitField: View {
    let title: String
    let value: String
    let axis: Axis
    let commit: (String) -> Void
    @State private var draft: String? = nil
    @FocusState private var focused: Bool

    public init(title: String, value: String, axis: Axis = .horizontal, commit: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.axis = axis
        self.commit = commit
    }

    public var body: some View {
        TextField(title, text: Binding(get: { draft ?? value }, set: { draft = $0 }), axis: axis)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    save()
                }
            }
            .onDisappear(perform: save)
    }

    private func save() {
        guard let text = draft else { return }
        draft = nil
        if text != value {
            commit(text)
        }
    }
}

#if DEBUG
#Preview("Labels and Fields") {
    Form {
        ProjectLabel(ledger: PreviewData.ledger, projectID: PreviewData.website)
        ProjectLabel(ledger: PreviewData.ledger, projectID: PreviewData.internalWork)
        ProjectLabel(ledger: PreviewData.ledger, projectID: nil)
        TagList(tags: ["design", "client-call"])
        TagList(tags: ["design", "#42"], links: ["#42": URL(string: "https://github.com/acme/website/issues/42")!])
        TagList(tags: ["design", "client-call", "#42", "#57", "research", "workshop", "follow-up"], wraps: true)
            .frame(width: 200, alignment: .leading)
        CommitField(title: "Note", value: "Wireframe review, round 2") { _ in }
    }
}
#endif

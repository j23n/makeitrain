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
            ProjectDot(ledger: ledger, projectID: projectID)
            Text(ledger.projectTitle(projectID))
                .lineLimit(1)
                .foregroundStyle(projectID == nil ? .secondary : .primary)
        }
    }
}

/// A project's color as a dot, or a ring for no project, as pickers show
/// "No Project". The ring keeps unassigned entries apart from a gray
/// project. The dot grows with Dynamic Type, like the text beside it.
struct ProjectDot: View {
    let color: Color?
    @ScaledMetric private var size: CGFloat = 8

    init(ledger: Ledger, projectID: UUID?) {
        color = projectID.map { ledger.color(ofProject: $0) }
    }

    var body: some View {
        Group {
            if let color {
                Circle()
                    .fill(color)
            } else {
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

#if DEBUG
#Preview("Project Labels") {
    Form {
        ProjectLabel(ledger: PreviewData.ledger, projectID: PreviewData.website)
        ProjectLabel(ledger: PreviewData.ledger, projectID: PreviewData.internalWork)
        ProjectLabel(ledger: PreviewData.ledger, projectID: PreviewData.admin)
        ProjectLabel(ledger: PreviewData.ledger, projectID: nil)
    }
}
#endif

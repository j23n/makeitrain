import SwiftUI
import TrackerCore

// Pieces the month and year reports share on the Mac, iPhone and iPad,
// some of them with the projects' pages.

/// What a report covers, as a menu's items: everything, or some clients
/// and projects.
public struct ReportFilterItems: View {
    let state: ReportState

    public init(state: ReportState) {
        self.state = state
    }

    public var body: some View {
        let ledger = state.model.ledger
        Button("Everything") {
            state.clients = []
            state.projects = []
            state.tags = []
        }
        Section("Clients") {
            ForEach(ledger.liveClients()) { client in
                Toggle(client.name, isOn: Binding(
                    get: { state.clients.contains(client.id) },
                    set: { on in
                        if on { state.clients.insert(client.id) } else { state.clients.remove(client.id) }
                    }
                ))
            }
        }
        Section("Projects") {
            ForEach(ledger.pickerProjects()) { project in
                Toggle(ledger.projectTitle(project.id), isOn: Binding(
                    get: { state.projects.contains(project.id) },
                    set: { on in
                        if on { state.projects.insert(project.id) } else { state.projects.remove(project.id) }
                    }
                ))
            }
        }
    }
}

/// A line of a report's breakdown by name: a tag that refers to an issue
/// as a link to it, anything else after its project's color.
public struct ReportGroupTitle: View {
    let group: ReportGroup
    let state: ReportState
    let spacing: CGFloat

    public init(_ group: ReportGroup, in state: ReportState, spacing: CGFloat = 6) {
        self.group = group
        self.state = state
        self.spacing = spacing
    }

    public var body: some View {
        if case let .tag(key) = group.kind, let url = state.report.issueURL(forTag: key, in: state.model.ledger) {
            Link(destination: url) {
                Text("\(group.title) ↗")
                    .foregroundStyle(Theme.tag)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: spacing) {
                if let color = group.color {
                    TintDot(ProjectTint(hex: color))
                }
                Text(group.title)
                    .lineLimit(1)
            }
        }
    }
}

extension ReportState {
    /// The name for the report's CSV file, such as "Acme 2026-09-01 to
    /// 2026-09-30".
    public var csvFileName: String {
        "\(title) \(range.lowerBound) to \(range.upperBound)"
    }
}

/// A value as a bar on a track as long as the highest value, as for the
/// lines of a breakdown.
public struct ShareBar: View {
    let value: Int64
    let highest: Int64
    let color: Color
    let height: CGFloat

    public init(_ value: Int64, of highest: Int64, color: Color, height: CGFloat) {
        self.value = value
        self.highest = highest
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(value) / CGFloat(max(highest, 1)))
            }
        }
        .frame(height: height)
    }
}

/// The mark for time counted twice, as on a day whose entries overlap:
/// stripes in an amber outline, `size` points square.
public struct OverlapSwatch: View {
    let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let corner: CGFloat = size >= 12 ? 3 : 2
        Hatching()
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.amber))
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

/// The time at which the charts' bars are full, in milliseconds.
public enum ChartScale {
    /// A day's bar, at 10½ hours.
    public static let fullDay: Int64 = 10 * 3_600_000 + 30 * 60_000
    /// A week's bar, at 40 hours unless a week shown is longer.
    public static let fullWeek: Int64 = 40 * 3_600_000
    /// A week longer than 50 hours is marked as long.
    public static let longWeek: Int64 = 50 * 3_600_000
}

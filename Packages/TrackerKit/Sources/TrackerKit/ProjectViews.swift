import SwiftUI
import TrackerCore

// The parts of the pages of projects and clients, shared by the Mac and the
// iPad.

/// A project's color as a rounded square with the project's first letter,
/// heading its page, or a dashed square for the entries without a project.
public struct ProjectBadge: View {
    let name: String
    let color: Color?
    @ScaledMetric private var size: CGFloat = 44

    /// `color` nil draws the dashed square.
    public init(name: String, color: Color?) {
        self.name = name
        self.color = color
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        Group {
            if let color {
                shape
                    .fill(color)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            } else {
                shape
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A client's symbol on a rounded square, heading its page.
public struct ClientBadge: View {
    @ScaledMetric private var size: CGFloat = 44

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The time of a project or client this week, this month and in all, with
/// how many entries make it up and since when.
public struct ProjectFigures: View {
    let overview: ProjectOverview

    public init(overview: ProjectOverview) {
        self.overview = overview
    }

    public var body: some View {
        HStack(spacing: 12) {
            FigureTile("This Week", detail: overview.isRunning ? "With the running timer" : nil) {
                DurationText(overview.thisWeek, size: 30)
            }
            FigureTile("This Month") {
                DurationText(overview.thisMonth, size: 30)
            }
            FigureTile("All Time", detail: since) {
                DurationText(overview.total, size: 30)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Such as "163 entries since Jun 15, 2026".
    private var since: String {
        guard let first = overview.firstDay else { return "No entries yet" }
        let entries = overview.entryCount == 1 ? "1 entry" : "\(overview.entryCount.formatted()) entries"
        return "\(entries) since \(Format.longDay(first))"
    }
}

/// The last twelve weeks of a project or client on a panel, each week's
/// total over its bar, stacked by project.
public struct WeeksChart: View {
    let overview: ProjectOverview
    let height: CGFloat

    public init(overview: ProjectOverview, height: CGFloat = 110) {
        self.overview = overview
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 12 Weeks")
                .font(.headline)
            BarChart(columns: overview.weeks, height: height)
        }
        .card()
    }
}

/// A project's tags on panels, each with its time, its entries and a bar,
/// the busiest first: the plain tags, then for each repository the tags
/// that refer to its issues, by number. A long list shows its busiest
/// until asked for all. Clicking a tag selects it, for its settings; an
/// issue's arrow opens it on GitHub.
public struct ProjectTagList: View {
    let overview: ProjectOverview
    /// The bars', the project's.
    let color: Color
    /// The selected tag's id.
    @Binding var selection: String?
    /// The lists showing all their tags: "tags", or a repository's id.
    @State private var expanded: Set<String> = []
    @ScaledMetric private var nameWidth: CGFloat = 180
    @ScaledMetric private var numberWidth: CGFloat = 64
    @ScaledMetric private var figureWidth: CGFloat = 84

    /// How many tags a long list shows until asked for all.
    static let shortList = 8

    public init(overview: ProjectOverview, color: Color, selection: Binding<String?>) {
        self.overview = overview
        self.color = color
        _selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // With only issue tags, the repositories are the whole list.
            if !overview.tags.isEmpty || overview.untagged > 0 || overview.repositories.isEmpty {
                tagsCard
            }
            ForEach(overview.repositories) { repository in
                repositoryCard(repository)
            }
        }
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags")
                .font(.headline)
            Text("Select a tag to rename, merge or remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            if overview.tags.isEmpty, overview.untagged == 0 {
                Text("No tags yet. The tags on the entries show up here with their time.")
                    .foregroundStyle(.secondary)
            } else {
                let maximum = max(overview.tags.map(\.milliseconds).max() ?? 0, overview.untagged)
                ForEach(shown(overview.tags, in: "tags")) { tag in
                    row(tag, title: tag.name, width: nameWidth, maximum: maximum)
                }
                moreButton(count: overview.tags.count, in: "tags", noun: "Tags")
                if overview.untagged > 0 {
                    untaggedRow(maximum: maximum)
                }
            }
        }
        .card()
    }

    private func repositoryCard(_ repository: ProjectOverview.Repository) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(repository.title, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("\(repository.issues.count == 1 ? "1 issue" : "\(repository.issues.count) issues") · \(Format.duration(repository.milliseconds))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.bottom, 6)
            let maximum = repository.issues.map(\.milliseconds).max() ?? 0
            ForEach(shown(repository.issues, in: repository.id)) { issue in
                row(issue, title: issue.number.map { "#\($0)" } ?? issue.name, width: numberWidth, maximum: maximum)
            }
            moreButton(count: repository.issues.count, in: repository.id, noun: "Issues")
        }
        .card()
    }

    /// A tag with its bar, time and entries, which selects it when clicked,
    /// and an arrow that opens its issue.
    private func row(_ tag: ProjectOverview.Tag, title: String, width: CGFloat, maximum: Int64) -> some View {
        let selected = selection == tag.id
        return HStack(spacing: 8) {
            Button {
                selection = selected ? nil : tag.id
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: width, alignment: .leading)
                    ShareBar(tag.milliseconds, of: maximum, color: color)
                    Text(Format.duration(tag.milliseconds))
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: figureWidth, alignment: .trailing)
                    Text(tag.count == 1 ? "1 entry" : "\(tag.count) entries")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: figureWidth, alignment: .trailing)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(selected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tag.name)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let url = tag.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Open \(tag.name) on GitHub")
                .accessibilityLabel(Text("Open \(tag.name) on GitHub"))
            }
        }
    }

    /// The time of the entries without tags, which has nothing to select.
    private func untaggedRow(maximum: Int64) -> some View {
        HStack(spacing: 12) {
            Text("Untagged")
                .foregroundStyle(.secondary)
                .frame(width: nameWidth, alignment: .leading)
            ShareBar(overview.untagged, of: maximum, color: .gray)
            Text(Format.duration(overview.untagged))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: figureWidth, alignment: .trailing)
            Color.clear
                .frame(width: figureWidth, height: 1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func moreButton(count: Int, in list: String, noun: String) -> some View {
        if count > Self.shortList {
            Button(expanded.contains(list) ? "Show Fewer \(noun)" : "Show All \(count) \(noun)") {
                if expanded.contains(list) {
                    expanded.remove(list)
                } else {
                    expanded.insert(list)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    /// A list's tags, or its busiest until it's asked for all.
    private func shown(_ tags: [ProjectOverview.Tag], in list: String) -> [ProjectOverview.Tag] {
        expanded.contains(list) ? tags : Array(tags.prefix(Self.shortList))
    }
}

#if DEBUG
#Preview("A Freelancer's Project") {
    let overview = PreviewData.overview(of: [PreviewData.quotlify], in: PreviewData.ownerLedger)
    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ProjectBadge(name: "Quotlify", color: Color(hex: "#4F7CAC"))
                ClientBadge()
                ProjectBadge(name: "Unassigned", color: nil)
            }
            ProjectFigures(overview: overview)
            WeeksChart(overview: overview)
            ProjectTagList(overview: overview, color: Color(hex: "#4F7CAC"), selection: .constant("daily"))
        }
        .padding()
    }
    .frame(width: 820, height: 1000)
}

#Preview("A Project's Tags and Issues") {
    let overview = PreviewData.overview(of: [PreviewData.mobileApp], in: PreviewData.ledger)
    return ProjectTagList(overview: overview, color: Color(hex: "#C0504D"), selection: .constant(nil))
        .padding()
        .frame(width: 720)
}

#Preview("No Tags") {
    let overview = PreviewData.overview(of: [PreviewData.internalWork], in: PreviewData.ledger)
    return ProjectTagList(overview: overview, color: Color(hex: "#8064A2"), selection: .constant(nil))
        .padding()
        .frame(width: 720)
}
#endif

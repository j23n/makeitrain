import SwiftUI
import TrackerCore
import TrackerKit

/// The top of the week, month and year: the days shown as a title, the
/// arrows that step them, Today when they're elsewhere, then the screen's
/// filter and what its colors mean, and its own figures at the end. The
/// title is as wide as the widest it can be in the year, the same on all
/// three, so the arrows stay put while stepping and switching.
///
/// It's one line while the title, Today, the filter and the figures fit at
/// their own size, and two lines otherwise, with the filter and the figures
/// on the second. What the colors mean goes between them where there's
/// room. The lines depend on the window's width and the parts' own, not on
/// the legend or whether Today shows, so stepping the month or year leaves
/// them as they are; the week's figures are wider with corrections.
struct ScreenHeader<Filter: View, Legend: View, Trailing: View>: View {
    let title: String
    /// The titles the title's room fits.
    let widest: [String]
    let previousTitle: String
    let nextTitle: String
    let showsToday: Bool
    let step: (Int) -> Void
    let today: () -> Void
    let filter: Filter
    let legend: Legend
    let trailing: Trailing

    init(
        _ title: String,
        year: Int,
        firstWeekday: Int,
        previous previousTitle: String,
        next nextTitle: String,
        showsToday: Bool,
        step: @escaping (Int) -> Void,
        today: @escaping () -> Void,
        @ViewBuilder filter: () -> Filter,
        @ViewBuilder legend: () -> Legend,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        widest = ScreenTitles.widest(in: year, firstWeekday: firstWeekday)
        self.previousTitle = previousTitle
        self.nextTitle = nextTitle
        self.showsToday = showsToday
        self.step = step
        self.today = today
        self.filter = filter()
        self.legend = legend()
        self.trailing = trailing()
    }

    var body: some View {
        // One of each part, so the typed report's field keeps what's typed
        // and its focus as the header changes lines.
        ScreenHeaderLayout(showsToday: showsToday) {
            navigation
            Button("Today", action: today)
                .buttonStyle(ChoiceButtonStyle(compact: true))
                .lineLimit(1)
                .fixedSize()
                // Kept while hidden, for its room.
                .opacity(showsToday ? 1 : 0)
                .disabled(!showsToday)
                .accessibilityHidden(!showsToday)
            HStack(spacing: 12) { filter }
            // The legend where it fits, or nothing.
            ViewThatFits(in: .horizontal) {
                legend
                Color.clear.frame(width: 0, height: 0)
            }
            HStack(spacing: 12) { trailing }
        }
    }

    /// The title and the arrows that step it.
    private var navigation: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .leading) {
                ForEach(widest, id: \.self) { title in
                    Text(title).hidden()
                }
                .accessibilityHidden(true)
                Text(title)
            }
            .font(.system(size: 19, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            HStack(spacing: 2) {
                stepButton("chevron.left", previousTitle, -1)
                stepButton("chevron.right", nextTitle, 1)
            }
        }
    }

    private func stepButton(_ systemImage: String, _ title: String, _ direction: Int) -> some View {
        Button {
            step(direction)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

/// Where the screen header's parts go: the title with its arrows, Today,
/// the filter, the legend and the figures, in that order. On one line when
/// all but the legend fit at their own size, Today counted even while it's
/// hidden, and otherwise the filter, the legend and the figures on a second
/// line. The figures are at the end of their line, and the legend gets the
/// room between them and the filter.
struct ScreenHeaderLayout: Layout {
    let showsToday: Bool
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 10

    /// The parts' own sizes, by their order.
    private struct Parts {
        let navigation, today, filter, legend, trailing: CGSize

        init(_ subviews: Subviews) {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            func size(_ index: Int) -> CGSize {
                sizes.indices.contains(index) ? sizes[index] : .zero
            }
            navigation = size(0)
            today = size(1)
            filter = size(2)
            legend = size(3)
            trailing = size(4)
        }
    }

    /// The width the header needs on one line, leaving out the legend.
    private func oneLineWidth(_ parts: Parts) -> CGFloat {
        parts.navigation.width + spacing + parts.today.width + spacing + parts.filter.width + spacing + parts.trailing.width
    }

    /// Whether the header fits on one line `width` points wide.
    private func fitsOneLine(_ parts: Parts, width: CGFloat) -> Bool {
        oneLineWidth(parts) <= width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let parts = Parts(subviews)
        // The width offered, or its own for none or an unlimited one.
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if fitsOneLine(parts, width: offered ?? .infinity) {
            let height = [parts.navigation, parts.today, parts.filter, parts.legend, parts.trailing].map(\.height).max() ?? 0
            return CGSize(width: offered ?? oneLineWidth(parts) + spacing + parts.legend.width, height: height)
        }
        let first = max(parts.navigation.height, parts.today.height)
        let second = [parts.filter, parts.legend, parts.trailing].map(\.height).max() ?? 0
        return CGSize(width: offered ?? oneLineWidth(parts), height: first + lineSpacing + second)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 5 else { return }
        let parts = Parts(subviews)
        let oneLine = fitsOneLine(parts, width: bounds.width)
        // The middle of each line.
        let firstLine: CGFloat
        let secondLine: CGFloat
        if oneLine {
            firstLine = bounds.midY
            secondLine = bounds.midY
        } else {
            let firstHeight = max(parts.navigation.height, parts.today.height)
            firstLine = bounds.minY + firstHeight / 2
            let secondHeight = [parts.filter, parts.legend, parts.trailing].map(\.height).max() ?? 0
            secondLine = bounds.maxY - secondHeight / 2
        }

        func place(_ index: Int, x: CGFloat, y: CGFloat, size: CGSize) {
            subviews[index].place(at: CGPoint(x: x, y: y), anchor: .leading, proposal: ProposedViewSize(size))
        }

        var x = bounds.minX
        place(0, x: x, y: firstLine, size: parts.navigation)
        x += parts.navigation.width + spacing
        place(1, x: x, y: firstLine, size: parts.today)
        if showsToday {
            x += parts.today.width + spacing
        }
        if !oneLine {
            x = bounds.minX
        }
        place(2, x: x, y: secondLine, size: parts.filter)
        x += parts.filter.width + spacing
        let trailingX = bounds.maxX - parts.trailing.width
        place(4, x: trailingX, y: secondLine, size: parts.trailing)
        let legendWidth = max(0, trailingX - spacing - x)
        place(3, x: x, y: secondLine, size: CGSize(width: legendWidth, height: parts.legend.height))
    }
}

/// Which clients and projects a screen shows, as a menu on a button:
/// "Everything", or their names.
struct FilterMenu: View {
    let model: AppModel
    let title: String
    /// Whether the screen leaves anything out, which the button shows.
    let isFiltered: Bool
    @Binding var clients: Set<UUID>
    @Binding var projects: Set<UUID>
    /// What "Everything" does.
    let clear: () -> Void

    var body: some View {
        Menu {
            ReportFilterItems(model: model, clients: $clients, projects: $projects, clear: clear)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isFiltered ? Theme.accent : Theme.text2)
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(isFiltered ? Theme.accent.opacity(0.12) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isFiltered ? Theme.accentLine : Theme.strongLine))
            .contentShape(Rectangle())
        }
        .plainMenu()
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Clients and projects shown")
    }
}

extension FilterMenu {
    /// The menu for the window's own filter, which the week, month and year
    /// share.
    init(model: AppModel, navigator: Navigator) {
        self.init(
            model: model,
            title: ReportState.title(clients: navigator.clients, projects: navigator.projects, in: model.ledger) ?? "Everything",
            isFiltered: !navigator.clients.isEmpty || !navigator.projects.isEmpty,
            clients: Bindable(navigator).clients,
            projects: Bindable(navigator).projects
        ) {
            navigator.clients = []
            navigator.projects = []
        }
    }

    /// The menu for a report's filter, which also clears its tags.
    init(state: ReportState) {
        self.init(
            model: state.model,
            title: state.title,
            isFiltered: !state.clients.isEmpty || !state.projects.isEmpty || !state.tags.isEmpty,
            clients: Bindable(state).clients,
            projects: Bindable(state).projects
        ) {
            state.clients = []
            state.projects = []
            state.tags = []
        }
    }
}

/// The titles a screen header's title can have in a year, for its room:
/// a week across each month's end, the year's first and last, each month,
/// and a day of each weekday.
enum ScreenTitles {
    static func widest(in year: Int, firstWeekday: Int) -> [String] {
        let months = (1...12).map { ReportPeriod.month.range(containing: LocalDate(year: year, month: $0, day: 1), firstWeekday: firstWeekday) }
        // The year's first week as well as its last, since one of them
        // always crosses a new year.
        let weeks = months.map { ReportPeriod.week.range(containing: $0.upperBound, firstWeekday: firstWeekday) }
            + [ReportPeriod.week.range(containing: LocalDate(year: year, month: 1, day: 1), firstWeekday: firstWeekday)]
        let days = (0..<7).map { LocalDate(year: year, month: 9, day: 21).adding(days: $0) }
        return Array(Set(weeks.map(Format.days) + months.map(Format.days) + days.map { Format.days($0...$0) })).sorted()
    }
}

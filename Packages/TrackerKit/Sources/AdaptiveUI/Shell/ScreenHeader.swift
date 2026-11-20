import SwiftUI
import TrackerCore
import TrackerKit

/// The top of the week, month and year: the days shown as a title, the
/// arrows that step them, Today when they're elsewhere, then the screen's
/// filter and what its colors mean, and its own figures at the end. The
/// title is as wide as the widest it can be in the year, the same on all
/// three, so the arrows stay put while stepping and switching.
///
/// It's one line while it fits. As the window narrows, the legend is left
/// out first, then the filter, legend and figures move to a second line,
/// and last the legend is left out of that too. The title and Today keep
/// their size.
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
        // The first arrangement whose parts fit side by side at their own
        // size, or the last.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                navigation
                filter
                legend
                Spacer(minLength: 12)
                trailing
            }
            HStack(alignment: .center, spacing: 12) {
                navigation
                filter
                Spacer(minLength: 12)
                trailing
            }
            twoLines(legend: true)
            twoLines(legend: false)
        }
    }

    /// The title, the arrows and Today on a line of their own, over the
    /// filter, the legend if asked, and the figures.
    private func twoLines(legend showsLegend: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                navigation
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 12) {
                filter
                if showsLegend {
                    legend
                }
                Spacer(minLength: 12)
                trailing
            }
        }
    }

    /// The title, the arrows that step it, and Today.
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
            if showsToday {
                Button("Today", action: today)
                    .buttonStyle(ChoiceButtonStyle(compact: true))
                    .lineLimit(1)
                    .fixedSize()
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

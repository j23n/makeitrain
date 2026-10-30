import SwiftUI
import TrackerCore
import TrackerKit

/// The top of the week, month and year: the days shown as a title, the
/// arrows that step them, Today when they're elsewhere, then the screen's
/// filter and what its colors mean, and its own figures at the end.
struct ScreenHeader<Content: View, Trailing: View>: View {
    let title: String
    let previousTitle: String
    let nextTitle: String
    let showsToday: Bool
    let step: (Int) -> Void
    let today: () -> Void
    let content: Content
    let trailing: Trailing

    init(
        _ title: String,
        previous previousTitle: String,
        next nextTitle: String,
        showsToday: Bool,
        step: @escaping (Int) -> Void,
        today: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.previousTitle = previousTitle
        self.nextTitle = nextTitle
        self.showsToday = showsToday
        self.step = step
        self.today = today
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 2) {
                stepButton("chevron.left", previousTitle, -1)
                stepButton("chevron.right", nextTitle, 1)
            }
            if showsToday {
                Button("Today", action: today)
                    .buttonStyle(ChoiceButtonStyle(compact: true))
            }
            content
            Spacer(minLength: 12)
            trailing
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

    private var isFiltered: Bool {
        !clients.isEmpty || !projects.isEmpty
    }
}

extension FilterMenu {
    /// The menu for the window's own filter, which the week, month and year
    /// share.
    init(model: AppModel, navigator: Navigator) {
        self.init(
            model: model,
            title: ReportState.title(clients: navigator.clients, projects: navigator.projects, in: model.ledger) ?? "Everything",
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
            clients: Bindable(state).clients,
            projects: Bindable(state).projects
        ) {
            state.clients = []
            state.projects = []
            state.tags = []
        }
    }
}

#if os(iOS)
import Observation
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// The iPhone's tabs.
enum PhoneTab: Hashable {
    case today, week, month, projects
}

/// A page pushed on the Projects tab.
enum PhoneProjectRoute: Hashable {
    case project(UUID)
    case archived
}

/// What the command line reads: a line to start, switch, stop or log, or
/// a report for the Month tab.
enum PhoneCommandMode: Hashable {
    case command, report
}

/// Where the iPhone app is: the tab, the week and month shown, the
/// projects' pages, and whether the command line is open. The week and the
/// month are kept here so a tab finds them as it left them.
@MainActor
@Observable
final class PhoneRouter {
    var tab: PhoneTab = .today
    /// Today's entries and what needs correcting on them.
    let today: WeekModel
    /// The week the Week tab shows, and the day picked in it.
    let week: WeekModel
    var weekDay: LocalDate
    /// The report the Month tab shows.
    let month: ReportState
    /// The pages pushed on the Projects tab.
    var projectsPath: [PhoneProjectRoute] = []
    var showsSettings = false
    var commandOpen = false
    var commandMode: PhoneCommandMode = .command
    /// Changing it puts the keyboard in the command line.
    var focusRequest = 0

    init(model: AppModel) {
        let today = model.today
        self.today = WeekModel(model: model, days: today...today)
        week = WeekModel(model: model, days: ReportPeriod.week.range(containing: today, firstWeekday: model.firstWeekday))
        weekDay = today
        month = ReportState(model: model, range: ReportPeriod.month.range(containing: today, firstWeekday: model.firstWeekday), period: .month)
    }

    /// Opens the command line, with a line typed in, or for a report.
    func openCommandLine(mode: PhoneCommandMode = .command) {
        commandMode = mode
        commandOpen = true
        focusRequest += 1
    }

    /// Shows a day on the Week tab, with one of its corrections selected.
    func showWeek(_ day: LocalDate, correction: String? = nil, firstWeekday: Int) {
        weekDay = day
        week.show(ReportPeriod.week.range(containing: day, firstWeekday: firstWeekday))
        if let correction {
            week.selectedCorrection = correction
        } else if let first = week.corrections.first(where: { $0.day == day }) {
            week.selectedCorrection = first.id
        }
        tab = .week
    }
}

/// The iPhone app: Today, Week, Month and Projects, with the command line
/// floating over the tab bar, opening over everything when tapped.
struct PhoneRoot: View {
    let model: AppModel
    @State private var router: PhoneRouter
    @State private var line: CommandLineModel
    /// What needs correcting this week, for the Week tab's badge.
    @State private var weekCorrections = 0

    init(model: AppModel) {
        self.model = model
        _router = State(initialValue: PhoneRouter(model: model))
        _line = State(initialValue: CommandLineModel(model: model))
        UITabBarItem.appearance().badgeColor = UIColor(Theme.amber)
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $router.tab) {
                PhoneToday(model: model, router: router)
                    .tabItem { Label("Today", systemImage: "clock") }
                    .tag(PhoneTab.today)
                PhoneWeek(model: model, router: router)
                    .tabItem { Label("Week", systemImage: "calendar.day.timeline.left") }
                    .badge(weekCorrections)
                    .tag(PhoneTab.week)
                PhoneMonth(model: model, router: router)
                    .tabItem { Label("Month", systemImage: "calendar") }
                    .tag(PhoneTab.month)
                PhoneProjects(model: model, router: router)
                    .tabItem { Label("Projects", systemImage: "folder") }
                    .tag(PhoneTab.projects)
            }
            .tint(Theme.accent)
            if router.commandOpen {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeCommandLine)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                PhoneCommandSheet(model: model, router: router, line: line, close: closeCommandLine)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: router.commandOpen)
        .sheet(isPresented: $router.showsSettings) {
            PhoneSettings(model: model)
        }
        .onAppear(perform: countCorrections)
        .onChange(of: model.revision) {
            line.refresh()
            router.today.refresh()
            router.week.refresh()
            router.month.refresh()
            countCorrections()
        }
        .onChange(of: model.preferences.skippedCorrections) {
            router.today.refresh(force: true)
            router.week.refresh(force: true)
            countCorrections()
        }
        .onChange(of: model.today) { _, today in
            router.today.show(today...today)
            countCorrections()
        }
        .onChange(of: model.request, initial: true) { _, request in
            handle(request)
        }
    }

    private func closeCommandLine() {
        router.commandOpen = false
        line.clear()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func countCorrections() {
        let thisWeek = ReportPeriod.week.range(containing: model.today, firstWeekday: model.firstWeekday)
        weekCorrections = model.corrections(on: thisWeek).count
    }

    /// Does what another part of the app asked for, such as an App
    /// Intent opening the command line.
    private func handle(_ request: AppRequest?) {
        guard case let .command(text)? = request else { return }
        line.text = text
        router.openCommandLine()
        model.request = nil
    }
}
#endif

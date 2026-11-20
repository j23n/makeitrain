import Observation
import SwiftUI
import TrackerCore
import TrackerKit
#if os(iOS)
import UIKit
#endif

/// The iPhone's tabs.
enum PhoneTab: Hashable {
    case week, month, projects
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
    var tab: PhoneTab = .week
    /// The week the Week tab shows, and the day picked in it, which starts
    /// as today.
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

    /// Moves the Week tab to the new day when the date changes, unless
    /// another day is picked.
    func followDate(from previous: LocalDate, to today: LocalDate, firstWeekday: Int) {
        weekDay = week.follow(weekDay, from: previous, to: today, firstWeekday: firstWeekday)
    }
}

/// The narrow layout, on an iPhone, a narrow iPad window and a narrow Mac
/// window: Week, Month and Projects, with the command line floating over
/// the tab bar, opening over everything from the bottom when tapped. On
/// iPhone and iPad, Settings opens over it as a sheet; the Mac has its own
/// Settings window.
public struct PhoneRoot<Settings: View>: View {
    let model: AppModel
    let settings: Settings
    /// Where the app is, with the week's corrections. It's made once, as
    /// the app appears, and the tabs wait for it: made in an initializer, a
    /// new one would be built, and thrown away, whenever the view around it
    /// redraws.
    @State private var router: PhoneRouter?

    public init(model: AppModel, @ViewBuilder settings: () -> Settings) {
        self.model = model
        self.settings = settings()
    }

    public var body: some View {
        if let router {
            PhoneTabs(model: model, router: router, settings: settings)
        } else {
            // onAppear runs before the first frame is drawn, so this is
            // never seen.
            Color.clear
                .onAppear {
                    #if os(iOS)
                    UITabBarItem.appearance().badgeColor = UIColor(Theme.amber)
                    #endif
                    router = PhoneRouter(model: model)
                }
        }
    }
}

extension PhoneRoot where Settings == EmptyView {
    /// The narrow layout without a Settings sheet, as on the Mac.
    public init(model: AppModel) {
        self.init(model: model) { EmptyView() }
    }
}

/// The tabs and the command line over them, once the router is made.
private struct PhoneTabs<Settings: View>: View {
    let model: AppModel
    @Bindable var router: PhoneRouter
    let settings: Settings
    @State private var line: CommandLineModel
    /// What needs correcting this week, for the Week tab's badge.
    @State private var weekCorrections = 0

    init(model: AppModel, router: PhoneRouter, settings: Settings) {
        self.model = model
        self.router = router
        self.settings = settings
        _line = State(initialValue: CommandLineModel(model: model))
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $router.tab) {
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
            #if os(macOS)
            // Room for the window's buttons, since the title bar is hidden.
            .padding(.top, 28)
            #endif
            if router.commandOpen {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeCommandLine)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                // At the bottom, where the bar was tapped, above the
                // keyboard.
                PhoneCommandSheet(model: model, router: router, line: line, close: closeCommandLine)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: router.commandOpen)
        #if os(macOS)
        .background {
            // ⌘K opens the command line, as it puts the keyboard in the
            // wide layout's.
            Button("Command Line") { router.openCommandLine() }
                .keyboardShortcut("k")
                .opacity(0)
                .accessibilityHidden(true)
        }
        #endif
        .sheet(isPresented: $router.showsSettings) {
            settings
        }
        .onAppear(perform: countCorrections)
        .onChange(of: model.revision) {
            line.refresh()
            router.week.refresh()
            countCorrections()
        }
        .onChange(of: model.preferences.skippedCorrections) {
            router.week.refresh()
            countCorrections()
        }
        .onChange(of: model.today) { previous, today in
            router.followDate(from: previous, to: today, firstWeekday: model.firstWeekday)
            countCorrections()
        }
        .onChange(of: model.request, initial: true) { _, request in
            handle(request)
        }
    }

    private func closeCommandLine() {
        router.commandOpen = false
        line.clear()
        endTextEditing()
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

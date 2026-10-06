import Observation
import SwiftUI
import TrackerCore
import TrackerKit

/// How much time a screen shows, or the projects, as the top bar picks.
enum Zoom: String, CaseIterable, Identifiable {
    case day, week, month, year, projects

    var id: Self { self }

    /// The screen of this zoom around a day.
    func screen(today day: LocalDate) -> Screen {
        switch self {
        case .day: .day(day)
        case .week: .week(day)
        case .month: .month(day)
        case .year: .year(day.year)
        case .projects: .projects
        }
    }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .projects: "Projects"
        }
    }
}

/// What the main window shows.
enum Screen: Hashable {
    case day(LocalDate)
    case week(LocalDate)
    case month(LocalDate)
    case year(Int)
    case projects
    case project(UUID)

    var zoom: Zoom {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        case .projects, .project: .projects
        }
    }

    /// A day in what the screen shows, for keeping the place when zooming.
    var day: LocalDate? {
        switch self {
        case let .day(day), let .week(day), let .month(day): day
        case let .year(year): LocalDate(year: year, month: 1, day: 1)
        case .projects, .project: nil
        }
    }
}

/// Where the main window is, and where it was, for Back and Forward.
@MainActor
@Observable
final class Navigator {
    private(set) var screen: Screen
    private var back: [Screen] = []
    private var forward: [Screen] = []

    init(_ screen: Screen) {
        self.screen = screen
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// Shows a screen, remembering this one for Back.
    func go(_ next: Screen) {
        guard next != screen else { return }
        back.append(screen)
        if back.count > 50 {
            back.removeFirst()
        }
        forward = []
        screen = next
    }

    /// Shows a screen in place of this one, as stepping a week does.
    func replace(_ next: Screen) {
        screen = next
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(screen)
        screen = previous
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(screen)
        screen = next
    }

    /// Shows another zoom around the same day.
    func zoom(_ zoom: Zoom, today: LocalDate) {
        go(zoom.screen(today: screen.day ?? today))
    }
}

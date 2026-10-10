import Observation
import SwiftUI
import TrackerCore
import TrackerKit

/// How much time a screen shows, or the projects, as the top bar picks.
enum Zoom: String, CaseIterable {
    case day, week, month, year, projects

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

    /// The key that shows this zoom with ⌘, in the bar's order: 1 for Day
    /// through 5 for Projects.
    var shortcutKey: Character {
        Character(String((Zoom.allCases.firstIndex(of: self) ?? 0) + 1))
    }

    /// The zoom ⌘ and `key` show, if any.
    init?(shortcutKey key: Character) {
        guard let zoom = Zoom.allCases.first(where: { $0.shortcutKey == key }) else { return nil }
        self = zoom
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

    /// A day in what the screen shows, for keeping the place when zooming:
    /// the screen's own day, or for a year, today when it's in that year and
    /// otherwise today's date in it. The projects have no day, so zooming
    /// in from them goes to today.
    func day(today: LocalDate) -> LocalDate {
        switch self {
        case let .day(day), let .week(day), let .month(day):
            return day
        case let .year(year):
            var day = today
            day.year = year
            // February 29 in a year without one.
            if LocalDate(daysSince1970: day.daysSince1970) != day {
                day.day = 28
            }
            return day
        case .projects, .project:
            return today
        }
    }
}

/// Where the main window is, and where it was, for Back and Forward.
@MainActor
@Observable
final class Navigator {
    private(set) var screen: Screen
    /// An entry for the week shown next to select, as one "find" turned up.
    var entryToSelect: UUID?
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
        go(zoom.screen(today: screen.day(today: today)))
    }
}

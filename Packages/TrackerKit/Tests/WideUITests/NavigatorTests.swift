import Foundation
import Testing
import TrackerCore
import TrackerKit
@testable import WideUI

@MainActor
@Suite struct NavigatorTests {
    let monday = LocalDate(year: 2026, month: 9, day: 28)
    let thursday = LocalDate(year: 2026, month: 10, day: 1)
    let project = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test func backAndForwardRetraceWhereTheWindowWas() {
        let navigator = Navigator(.week(monday))
        #expect(!navigator.canGoBack)
        navigator.go(.projects)
        navigator.go(.project(project))
        #expect(navigator.canGoBack)
        #expect(!navigator.canGoForward)

        navigator.goBack()
        #expect(navigator.screen == .projects)
        navigator.goBack()
        #expect(navigator.screen == .week(monday))
        #expect(!navigator.canGoBack)
        navigator.goForward()
        #expect(navigator.screen == .projects)
        #expect(navigator.canGoForward)
    }

    @Test func goingSomewhereNewForgetsWhatWasAhead() {
        let navigator = Navigator(.week(monday))
        navigator.go(.projects)
        navigator.goBack()
        navigator.go(.month(monday))
        #expect(!navigator.canGoForward)
        navigator.goBack()
        #expect(navigator.screen == .week(monday))
    }

    @Test func showingTheSameScreenAgainAddsNothing() {
        let navigator = Navigator(.week(monday))
        navigator.go(.week(monday))
        #expect(!navigator.canGoBack)
    }

    @Test func steppingAWeekReplacesItRatherThanAddingToBack() {
        let navigator = Navigator(.projects)
        navigator.go(.week(monday))
        navigator.replace(.week(monday.adding(days: 7)))
        navigator.replace(.week(monday.adding(days: 14)))
        navigator.goBack()
        #expect(navigator.screen == .projects)
    }

    @Test func backRemembersFiftyScreens() {
        let navigator = Navigator(.week(monday))
        for offset in 1...60 {
            navigator.go(.day(monday.adding(days: offset)))
        }
        var steps = 0
        while navigator.canGoBack {
            navigator.goBack()
            steps += 1
        }
        #expect(steps == 50)
        #expect(navigator.screen == .day(monday.adding(days: 10)))
    }

    @Test func zoomingKeepsTheDay() {
        let navigator = Navigator(.week(thursday))
        navigator.zoom(.month, today: monday)
        #expect(navigator.screen == .month(thursday))
        navigator.zoom(.year, today: monday)
        #expect(navigator.screen == .year(2026))
        // The year keeps no day of its own: zooming in goes to today.
        navigator.zoom(.day, today: monday)
        #expect(navigator.screen == .day(monday))
        navigator.zoom(.projects, today: monday)
        #expect(navigator.screen == .projects)
        // The projects have no day, so zooming back in goes to today.
        navigator.zoom(.week, today: monday)
        #expect(navigator.screen == .week(monday))
    }

    @Test func aProjectsPageZoomsAsTheProjects() {
        #expect(Screen.project(project).zoom == .projects)
        #expect(Screen.project(project).day(today: thursday) == thursday)
        #expect(Zoom.year.screen(today: thursday) == .year(2026))
        #expect(Zoom.day.screen(today: thursday) == .day(thursday))
    }

    @Test func commandAndANumberShowEachZoom() throws {
        // ⌘1 to ⌘5, in the bar's order.
        #expect(Zoom.allCases.map(\.shortcutKey) == ["1", "2", "3", "4", "5"])
        #expect(Zoom(shortcutKey: "6") == nil)
        let navigator = Navigator(.week(thursday))
        let keys: [(Character, Screen)] = [
            ("3", .month(thursday)),
            ("1", .day(thursday)),
            ("4", .year(2026)),
            ("2", .week(monday)),
            ("5", .projects),
        ]
        for (key, screen) in keys {
            navigator.zoom(try #require(Zoom(shortcutKey: key)), today: monday)
            #expect(navigator.screen == screen)
        }
        // Back returns to the screen before.
        navigator.goBack()
        #expect(navigator.screen == .week(monday))
    }

    @Test func zoomingInFromThisYearGoesToToday() {
        for zoom in [Zoom.month, .week, .day] {
            let navigator = Navigator(.year(2026))
            navigator.zoom(zoom, today: thursday)
            #expect(navigator.screen == zoom.screen(today: thursday))
            navigator.goBack()
            #expect(navigator.screen == .year(2026))
        }
        // Zooming between the others still keeps the day shown.
        let navigator = Navigator(.year(2026))
        navigator.zoom(.week, today: thursday)
        navigator.replace(.week(monday.adding(days: -14)))
        navigator.zoom(.month, today: thursday)
        #expect(navigator.screen == .month(monday.adding(days: -14)))
    }

    @Test func zoomingInFromAnotherYearGoesToTodaysDateInIt() {
        #expect(Screen.year(2025).day(today: thursday) == LocalDate(year: 2025, month: 10, day: 1))
        let leapDay = LocalDate(year: 2028, month: 2, day: 29)
        #expect(Screen.year(2027).day(today: leapDay) == LocalDate(year: 2027, month: 2, day: 28))
        #expect(Screen.year(2024).day(today: leapDay) == LocalDate(year: 2024, month: 2, day: 29))
        let navigator = Navigator(.year(2025))
        navigator.zoom(.month, today: thursday)
        #expect(navigator.screen == .month(LocalDate(year: 2025, month: 10, day: 1)))
    }
}

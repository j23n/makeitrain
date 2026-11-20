import Foundation
import Testing
import TrackerCore
import TrackerKit
@testable import AdaptiveUI

/// The narrow layout's tabs opening where the wide layout was, and saying
/// where they are, for a window that changes layout as it's resized.
@MainActor
@Suite struct CompactRouterTests {
    let wednesday = LocalDate(year: 2026, month: 9, day: 16)
    let project = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test func opensOnTodaysWeekWithoutAPlace() {
        let model = PreviewData.model()
        let router = CompactRouter(model: model)
        #expect(router.tab == .week)
        #expect(router.weekDay == model.today)
        #expect(router.screen == .week(model.today))
    }

    @Test func opensAWeekOnItsDay() {
        let model = PreviewData.model()
        let router = CompactRouter(model: model, showing: .week(wednesday))
        #expect(router.tab == .week)
        #expect(router.weekDay == wednesday)
        #expect(router.week.days == ReportPeriod.week.range(containing: wednesday, firstWeekday: model.firstWeekday))
        #expect(router.screen == .week(wednesday))
    }

    @Test func opensAMonthOnTheMonthTab() {
        let model = PreviewData.model()
        let router = CompactRouter(model: model, showing: .month(wednesday))
        #expect(router.tab == .month)
        #expect(router.month.range == LocalDate(year: 2026, month: 9, day: 1)...LocalDate(year: 2026, month: 9, day: 30))
        #expect(router.month.period == .month)
        #expect(router.screen == .month(LocalDate(year: 2026, month: 9, day: 1)))
    }

    @Test func opensAYearOnTodaysMonthInIt() {
        let model = PreviewData.model()
        let year = model.today.year - 1
        let router = CompactRouter(model: model, showing: .year(year))
        #expect(router.tab == .month)
        #expect(router.month.range.lowerBound == LocalDate(year: year, month: model.today.month, day: 1))
    }

    @Test func opensTheProjectsAndAProjectsPage() {
        let model = PreviewData.model()
        let projects = CompactRouter(model: model, showing: .projects)
        #expect(projects.tab == .projects)
        #expect(projects.projectsPath.isEmpty)
        #expect(projects.screen == .projects)

        let page = CompactRouter(model: model, showing: .project(project))
        #expect(page.tab == .projects)
        #expect(page.projectsPath == [.project(project)])
        #expect(page.screen == .project(project))
    }

    @Test func saysWhereTheTabsMoved() {
        let model = PreviewData.model()
        let router = CompactRouter(model: model, showing: .week(wednesday))
        router.month.step(1)
        router.tab = .month
        #expect(router.screen == .month(LocalDate(year: 2026, month: 10, day: 1)))
        router.projectsPath = [.archived]
        router.tab = .projects
        #expect(router.screen == .projects)
    }
}

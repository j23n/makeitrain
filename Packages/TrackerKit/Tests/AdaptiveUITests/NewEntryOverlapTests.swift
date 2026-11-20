import Foundation
import Testing
import TrackerCore
import TrackerKit
@testable import AdaptiveUI

/// What a new entry drawn on the week overlaps, as its sidebar and its
/// sheet say it.
@MainActor
@Suite struct NewEntryOverlapTests {
    /// Monday, September 21, in the sample data, with Planning from 11:30
    /// to 12:15 and Sync engine from 13:00.
    let monday = LocalDate(year: 2026, month: 9, day: 21)

    func hm(_ hour: Int, _ minute: Int) -> Int {
        hour * 3600 + minute * 60
    }

    @Test func saysWhatANewEntryOverlapsAndForHowLong() {
        let model = PreviewData.model()
        let week = WeekModel(model: model, days: ReportPeriod.week.range(containing: monday, firstWeekday: model.firstWeekday))
        let draft = model.newEntryDraft(on: monday, startSecond: hm(12, 0), endSecond: hm(13, 30))
        let from = Format.time(secondOfDay: hm(12, 0))
        let to = Format.time(secondOfDay: hm(12, 15))
        // The first entry it overlaps, not the later one.
        #expect(NewEntryOverlap.text(for: draft, model: model, week: week) == "Overlaps Planning from \(from) to \(to).")
    }

    @Test func saysNothingForANewEntryThatOnlyTouchesAnother() {
        let model = PreviewData.model()
        let week = WeekModel(model: model, days: ReportPeriod.week.range(containing: monday, firstWeekday: model.firstWeekday))
        let draft = model.newEntryDraft(on: monday, startSecond: hm(12, 15), endSecond: hm(13, 0))
        #expect(NewEntryOverlap.text(for: draft, model: model, week: week) == nil)
    }
}

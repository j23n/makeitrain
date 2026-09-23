import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct FormattingTests {
    let minute: Int64 = 60000

    @Test func formatsDurationsAsHoursAndMinutes() {
        #expect(Format.duration(0) == "0:00")
        #expect(Format.duration(59999) == "0:00")
        #expect(Format.duration(5 * minute) == "0:05")
        #expect(Format.duration(125 * minute) == "2:05")
        #expect(Format.duration(-minute) == "0:00")
    }

    @Test func readsTypedDurations() {
        #expect(Format.parseDuration("1:30") == 90 * minute)
        #expect(Format.parseDuration(" 0:05 ") == 5 * minute)
        #expect(Format.parseDuration(":45") == 45 * minute)
        #expect(Format.parseDuration("1.5") == 90 * minute)
        #expect(Format.parseDuration("0,25") == 15 * minute)
        #expect(Format.parseDuration("2") == 120 * minute)
        #expect(Format.parseDuration("90m") == 90 * minute)
        #expect(Format.parseDuration("1h 30m") == 90 * minute)
        #expect(Format.parseDuration("1H30") == 90 * minute)
        #expect(Format.parseDuration("1.5h") == 90 * minute)
        #expect(Format.parseDuration("0") == 0)
    }

    @Test func rejectsWhatItCantRead() {
        for text in ["", "abc", "1:5", "1:60", "1:30:00", "-1", "h", "30m15", "1h 2x", "1e9"] {
            #expect(Format.parseDuration(text) == nil, "\(text)")
        }
    }

    @Test func readsTypedTimes() {
        let hour = 3600
        #expect(Format.parseTime("9:15") == 9 * hour + 15 * 60)
        #expect(Format.parseTime(" 09:15 ") == 9 * hour + 15 * 60)
        #expect(Format.parseTime("9.15") == 9 * hour + 15 * 60)
        #expect(Format.parseTime("915") == 9 * hour + 15 * 60)
        #expect(Format.parseTime("1730") == 17 * hour + 30 * 60)
        #expect(Format.parseTime("9") == 9 * hour)
        #expect(Format.parseTime("0") == 0)
        #expect(Format.parseTime("9:15:30") == 9 * hour + 15 * 60 + 30)
        #expect(Format.parseTime("24:00") == 24 * hour)
        // As the Mac shows times in English, with a narrow space before "PM".
        #expect(Format.parseTime("9:15\u{202F}PM") == 21 * hour + 15 * 60)
        #expect(Format.parseTime("9pm") == 21 * hour)
        #expect(Format.parseTime("9 a.m.") == 9 * hour)
        #expect(Format.parseTime("12:30 AM") == 30 * 60)
        #expect(Format.parseTime("12 PM") == 12 * hour)
    }

    @Test func rejectsTimesItCantRead() {
        for text in ["", ":", "abc", "9:5", "9:60", "25", "24:30", "13pm", "0am", "12345", "9:15:5", "-9", "９:15"] {
            #expect(Format.parseTime(text) == nil, "\(text)")
        }
    }

    @Test func typedTimesFallOnTheEntrysDayInItsZone() {
        // 22:00 to 01:00 in New York, when it's already the next day in Berlin.
        let start = DateTimeFormat.parse("2026-09-23T22:00:00-04:00")!
        let entry = Ledger(entries: [
            TimeEntry(start: start, end: start.adding(seconds: 3 * 3600), timeZone: "America/New_York", updated: start),
        ]).resolvedEntries()[0]
        #expect(entry.startAt(secondOfDay: 21 * 3600) == DateTimeFormat.parse("2026-09-23T21:00:00-04:00")!)
        #expect(entry.endAt(secondOfDay: 23 * 3600) == DateTimeFormat.parse("2026-09-23T23:00:00-04:00")!)
        // An end before the start is the next day.
        #expect(entry.endAt(secondOfDay: 2 * 3600) == DateTimeFormat.parse("2026-09-24T02:00:00-04:00")!)
        #expect(entry.endAt(secondOfDay: 22 * 3600) == DateTimeFormat.parse("2026-09-24T22:00:00-04:00")!)
        // Moving to another day keeps the wall-clock time.
        let day = LocalDate(year: 2026, month: 9, day: 1)
        #expect(entry.startOn(day) == DateTimeFormat.parse("2026-09-01T22:00:00-04:00")!)
    }
}

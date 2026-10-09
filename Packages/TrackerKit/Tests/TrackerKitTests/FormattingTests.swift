import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct FormattingTests {
    let minute: Int64 = 60000

    /// A duration with ordinary spaces, for comparing; it has spaces that
    /// don't break.
    func spaced(_ duration: String) -> String {
        duration.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test func formatsDurationsAsHoursAndMinutes() {
        #expect(Format.duration(0) == "0:00")
        #expect(Format.duration(59999) == "0:00")
        #expect(Format.duration(5 * minute) == "0:05")
        #expect(Format.duration(125 * minute) == "2:05")
        #expect(Format.duration(-minute) == "0:00")
        #expect(Format.duration(24 * 60 * minute - 1) == "23:59")
    }

    @Test func writesADayOrMoreWithUnits() {
        let hour = 60 * minute
        #expect(spaced(Format.duration(24 * hour)) == "24 h")
        #expect(spaced(Format.duration(42 * hour + 31 * minute)) == "42 h 31 m")
        #expect(spaced(Format.duration(574 * hour + 46 * minute + 59999)) == "574 h 46 m")
        #expect(spaced(Format.duration(100 * hour + 5 * minute)) == "100 h 5 m")
        // The hours and minutes stay together on one line.
        #expect(!Format.duration(42 * hour + 31 * minute).contains(" "))
    }

    @Test func writesASpanToItsEndOrToNow() {
        let zone = "Europe/Berlin"
        let start = DateTimeFormat.parse("2026-09-23T12:30:00+02:00")!
        let end = DateTimeFormat.parse("2026-09-23T12:55:00+02:00")!
        #expect(Format.span(start, end, zone: zone) == "\(Format.time(start, zone: zone))–\(Format.time(end, zone: zone))")
        #expect(Format.span(start, nil, zone: zone) == "\(Format.time(start, zone: zone))–now")
        let entry = TimeEntry(start: start, end: end, timeZone: "America/New_York", updated: start)
        #expect(Format.span(entry) == Format.span(start, end, zone: "America/New_York"))
    }

    @Test func readsBackWhatItWrites() {
        let hour = 60 * minute
        for duration in [5 * minute, 7 * hour + 45 * minute, 24 * hour, 574 * hour + 46 * minute] {
            #expect(Durations.parse(Format.duration(duration)) == duration)
        }
    }
}

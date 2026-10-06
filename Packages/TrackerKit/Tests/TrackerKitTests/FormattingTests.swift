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
        let parts = Format.durationParts(42 * hour + 31 * minute)
        #expect(parts.map { $0.number } == ["42", "31"])
        #expect(parts.map { $0.unit } == ["h", "m"])
        #expect(Format.durationParts(90 * minute).map { $0.unit } == [nil])
    }

    @Test func readsBackWhatItWrites() {
        let hour = 60 * minute
        for duration in [5 * minute, 7 * hour + 45 * minute, 24 * hour, 574 * hour + 46 * minute] {
            #expect(Durations.parse(Format.duration(duration)) == duration)
        }
    }

    @Test func readsTypedDurations() {
        #expect(Durations.parse("1:30") == 90 * minute)
        #expect(Durations.parse(" 0:05 ") == 5 * minute)
        #expect(Durations.parse(":45") == 45 * minute)
        #expect(Durations.parse("1.5") == 90 * minute)
        #expect(Durations.parse("0,25") == 15 * minute)
        #expect(Durations.parse("2") == 120 * minute)
        #expect(Durations.parse("90m") == 90 * minute)
        #expect(Durations.parse("1h 30m") == 90 * minute)
        #expect(Durations.parse("1H30") == 90 * minute)
        #expect(Durations.parse("1.5h") == 90 * minute)
        #expect(Durations.parse("0") == 0)
    }

    @Test func rejectsWhatItCantRead() {
        for text in ["", "abc", "1:5", "1:60", "1:30:00", "-1", "h", "30m15", "1h 2x", "1e9"] {
            #expect(Durations.parse(text) == nil, "\(text)")
        }
    }
}

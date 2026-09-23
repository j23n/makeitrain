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
}

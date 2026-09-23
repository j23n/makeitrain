import Foundation
import Testing
@testable import TrackerCore

@Suite struct TimestampTests {
    @Test func roundsDatesToTheMillisecond() {
        #expect(Timestamp(Date(timeIntervalSince1970: 1.0004)).milliseconds == 1000)
        #expect(Timestamp(Date(timeIntervalSince1970: 1.0006)).milliseconds == 1001)
        let time = Timestamp(milliseconds: 1_790_000_000_123)
        #expect(Timestamp(time.date) == time)
    }

    @Test func dropsMillisecondsTowardsThePast() {
        #expect(Timestamp(milliseconds: 1999).wholeSeconds.milliseconds == 1000)
        #expect(Timestamp(milliseconds: -1).wholeSeconds.milliseconds == -1000)
        #expect(Timestamp(milliseconds: -1000).wholeSeconds.milliseconds == -1000)
    }

    @Test func stampsBeatThePreviousStamp() {
        let now = t("2026-09-23T10:00:00Z")
        #expect(Timestamp.stamp(after: nil, now: now) == now)
        #expect(Timestamp.stamp(after: t("2026-09-23T09:00:00Z"), now: now) == now)
        // This device's clock is behind the one that made the previous version.
        #expect(Timestamp.stamp(after: t("2026-09-23T10:02:00Z"), now: now) == t("2026-09-23T10:02:00.001Z"))
    }
}

@Suite struct LocalDateTests {
    @Test func convertsDaysBothWays() {
        for days in stride(from: -800_000, through: 800_000, by: 97) {
            #expect(LocalDate(daysSince1970: days).daysSince1970 == days)
        }
    }

    @Test func knowsTheCalendar() {
        #expect(LocalDate(daysSince1970: 0) == LocalDate(year: 1970, month: 1, day: 1))
        #expect(LocalDate(year: 2000, month: 1, day: 1).daysSince1970 == 10957)
        #expect(LocalDate(year: 2024, month: 2, day: 28).adding(days: 1) == LocalDate(year: 2024, month: 2, day: 29))
        #expect(LocalDate(year: 2026, month: 2, day: 28).adding(days: 1) == LocalDate(year: 2026, month: 3, day: 1))
        #expect(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1) == LocalDate(year: 2027, month: 1, day: 1))
        #expect(LocalDate(year: 2026, month: 9, day: 23).weekday == 4) // Wednesday
        #expect(LocalDate(year: 1969, month: 12, day: 28).weekday == 1) // Sunday
        #expect(LocalDate(year: 2026, month: 9, day: 23).description == "2026-09-23")
    }

    @Test func parsesMonths() {
        #expect(MonthKey("2026-09") == MonthKey(year: 2026, month: 9))
        #expect(MonthKey(year: 2026, month: 9).fileName == "2026-09.json")
        for text in ["2026-13", "2026-00", "2026-9", "26-09", "2026-09 2", "2026-+9", "abcd-09", ""] {
            #expect(MonthKey(text) == nil, "\(text)")
        }
    }

    @Test func filesEntriesByTheirOwnTimeZone() {
        // 00:30 on Oct 1 in Berlin is still Sep 30 in New York.
        let instant = t("2026-10-01T00:30:00+02:00")
        let berlin = TimeEntry(start: instant, timeZone: "Europe/Berlin", updated: instant)
        let newYork = TimeEntry(start: instant, timeZone: "America/New_York", updated: instant)
        #expect(berlin.day == LocalDate(year: 2026, month: 10, day: 1))
        #expect(berlin.month == MonthKey(year: 2026, month: 10))
        #expect(newYork.day == LocalDate(year: 2026, month: 9, day: 30))
        #expect(newYork.month == MonthKey(year: 2026, month: 9))
    }
}

@Suite struct DateTimeFormatTests {
    @Test func writesTheZonesOffset() {
        let summer = t("2026-09-23T07:15:00Z")
        let winter = t("2026-01-15T08:00:00Z")
        #expect(DateTimeFormat.format(summer, zone: "Europe/Berlin") == "2026-09-23T09:15:00+02:00")
        #expect(DateTimeFormat.format(winter, zone: "Europe/Berlin") == "2026-01-15T09:00:00+01:00")
        #expect(DateTimeFormat.format(summer, zone: "America/New_York") == "2026-09-23T03:15:00-04:00")
        #expect(DateTimeFormat.format(summer, zone: "Asia/Kolkata") == "2026-09-23T12:45:00+05:30")
        #expect(DateTimeFormat.format(winter, zone: "Europe/London") == "2026-01-15T08:00:00+00:00")
        #expect(DateTimeFormat.formatUTC(summer) == "2026-09-23T07:15:00Z")
    }

    @Test func fallsBackToUTCForUnknownZones() {
        #expect(DateTimeFormat.format(t("2026-09-23T07:15:00Z"), zone: "Mars/Olympus_Mons") == "2026-09-23T07:15:00+00:00")
    }

    @Test func writesMillisecondsOnlyWhenThereAreSome() {
        #expect(DateTimeFormat.formatUTC(t("2026-09-23T07:15:00.412Z")) == "2026-09-23T07:15:00.412Z")
        #expect(DateTimeFormat.formatUTC(t("2026-09-23T07:15:00.040Z")) == "2026-09-23T07:15:00.040Z")
        #expect(DateTimeFormat.formatUTC(t("2026-09-23T07:15:00.000Z")) == "2026-09-23T07:15:00Z")
    }

    @Test func readsWhatItWrites() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<2000 {
            let time = Timestamp(milliseconds: Int64.random(in: -2_000_000_000_000...4_000_000_000_000, using: &rng))
            let offset = Int.random(in: -14 * 60...14 * 60, using: &rng) * 60
            #expect(DateTimeFormat.parse(DateTimeFormat.format(time, offsetSeconds: offset)) == time)
            #expect(DateTimeFormat.parse(DateTimeFormat.formatUTC(time)) == time)
        }
    }

    @Test func acceptsCommonVariants() {
        let expected = t("2026-09-23T07:15:00Z")
        #expect(DateTimeFormat.parse("2026-09-23t07:15:00z") == expected)
        #expect(DateTimeFormat.parse("2026-09-23 09:15:00+02:00") == expected)
        #expect(DateTimeFormat.parse("2026-09-23T07:15:00.000000000Z") == expected)
        #expect(DateTimeFormat.parse("2026-09-23T07:15:00.9Z") == expected.adding(milliseconds: 900))
        #expect(DateTimeFormat.parse("2026-09-23T07:15:00.12345Z") == expected.adding(milliseconds: 123))
    }

    @Test(arguments: [
        "", "yesterday", "2026-09-23", "2026-09-23T07:15:00", "2026-02-30T00:00:00Z",
        "2026-09-23T24:00:00Z", "2026-09-23T07:60:00Z", "2026-09-23T07:15:60Z",
        "2026-09-23T07:15:00+2:00", "2026-09-23T07:15:00+02:00 ", "2026-09-23T07:15:00.Z",
        "2026-9-23T07:15:00Z", "2026-09-23T07:15:00+0200", "2026-09-23T07:15:00.1234567890Z",
    ])
    func rejectsOtherText(text: String) {
        #expect(DateTimeFormat.parse(text) == nil)
    }
}

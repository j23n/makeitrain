/// ISO 8601 date-times as the data files write them, such as
/// "2026-09-23T09:15:00+02:00", with milliseconds (".412") only when there
/// are some.
public enum DateTimeFormat {
    /// `time` as wall-clock time in a time zone, with that zone's offset.
    public static func format(_ time: Timestamp, zone: String) -> String {
        format(time, offsetSeconds: Zones.offset(zone, at: time))
    }

    /// `time` as wall-clock time `offsetSeconds` east of UTC.
    public static func format(_ time: Timestamp, offsetSeconds: Int) -> String {
        // An offset with seconds can't be written; UTC names the same instant.
        guard offsetSeconds % 60 == 0 else { return formatUTC(time) }
        let minutes = abs(offsetSeconds) / 60
        let sign = offsetSeconds < 0 ? "-" : "+"
        return dateAndTime(time, offsetSeconds: offsetSeconds) + "\(sign)\(padded(minutes / 60, 2)):\(padded(minutes % 60, 2))"
    }

    /// `time` in UTC, ending in "Z".
    public static func formatUTC(_ time: Timestamp) -> String {
        dateAndTime(time, offsetSeconds: 0) + "Z"
    }

    private static func dateAndTime(_ time: Timestamp, offsetSeconds: Int) -> String {
        let local = time.local(offsetSeconds: offsetSeconds)
        var text = "\(local.date)T\(padded(local.hour, 2)):\(padded(local.minute, 2)):\(padded(local.second, 2))"
        if local.millisecond != 0 {
            text += ".\(padded(local.millisecond, 3))"
        }
        return text
    }

    /// Parses a date-time written as above.
    ///
    /// Also accepts a lowercase "t" or a space between date and time, a
    /// lowercase "z", and one to nine fraction digits; digits past the
    /// milliseconds are dropped. Returns nil for anything else, including
    /// a missing offset.
    public static func parse(_ text: String) -> Timestamp? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20 else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                guard index < bytes.count, (48...57).contains(bytes[index]) else { return nil }
                value = value * 10 + Int(bytes[index] - 48)
            }
            return value
        }
        func byte(_ index: Int, is character: Unicode.Scalar) -> Bool {
            index < bytes.count && bytes[index] == UInt8(ascii: character)
        }

        guard let year = number(0..<4), byte(4, is: "-"),
              let month = number(5..<7), byte(7, is: "-"),
              let day = number(8..<10),
              byte(10, is: "T") || byte(10, is: "t") || byte(10, is: " "),
              let hour = number(11..<13), byte(13, is: ":"),
              let minute = number(14..<16), byte(16, is: ":"),
              let second = number(17..<19),
              (1...12).contains(month), (1...LocalDate.daysIn(month: month, year: year)).contains(day),
              hour < 24, minute < 60, second < 60
        else { return nil }

        var index = 19
        var millisecond = 0
        if byte(index, is: ".") {
            index += 1
            let first = index
            while index < bytes.count, (48...57).contains(bytes[index]) {
                index += 1
            }
            let digits = index - first
            guard (1...9).contains(digits) else { return nil }
            for place in 0..<3 {
                millisecond = millisecond * 10 + (place < digits ? Int(bytes[first + place] - 48) : 0)
            }
        }

        let offsetSeconds: Int
        if byte(index, is: "Z") || byte(index, is: "z") {
            offsetSeconds = 0
            index += 1
        } else if byte(index, is: "+") || byte(index, is: "-") {
            guard let hours = number(index + 1..<index + 3), byte(index + 3, is: ":"),
                  let minutes = number(index + 4..<index + 6), hours < 24, minutes < 60
            else { return nil }
            offsetSeconds = (hours * 60 + minutes) * 60 * (byte(index, is: "-") ? -1 : 1)
            index += 6
        } else {
            return nil
        }
        guard index == bytes.count else { return nil }

        let days = Int64(LocalDate(year: year, month: month, day: day).daysSince1970)
        let millisecondOfDay = Int64(((hour * 60 + minute) * 60 + second) * 1000 + millisecond)
        return Timestamp(milliseconds: days * 86_400_000 + millisecondOfDay - Int64(offsetSeconds) * 1000)
    }
}

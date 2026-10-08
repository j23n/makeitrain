import Foundation

/// Durations as people type them.
public enum Durations {
    /// Reads a duration typed as "1:30", "1.5" (hours), "90m", "1h 30m" or
    /// "1h30". Milliseconds, or nil if it can't be read.
    public static func parse(_ text: String) -> Int64? {
        let typed = text.lowercased().filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return nil }
        if typed.contains(":") {
            let parts = typed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].count == 2,
                  let hours = parts[0].isEmpty ? 0 : Int(parts[0]), let minutes = Int(parts[1]),
                  hours >= 0, (0..<60).contains(minutes)
            else { return nil }
            return Int64(hours * 60 + minutes) * 60000
        }
        guard typed.contains("h") || typed.contains("m") else {
            guard let hours = Double(typed.replacingOccurrences(of: ",", with: ".")), hours >= 0, hours < 10000 else {
                return nil
            }
            return Int64((hours * 60).rounded()) * 60000
        }
        var minutes = 0.0
        var number = ""
        var sawHours = false
        for character in typed {
            if character.isASCII, character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
            } else if character == "h" || character == "m" {
                guard let value = Double(number) else { return nil }
                minutes += character == "h" ? value * 60 : value
                sawHours = sawHours || character == "h"
                number = ""
            } else {
                return nil
            }
        }
        if !number.isEmpty {
            // "1h30" means 1 hour 30 minutes.
            guard sawHours, let value = Double(number) else { return nil }
            minutes += value
        }
        guard minutes < 600_000 else { return nil }
        return Int64(minutes.rounded()) * 60000
    }

    /// Reads a duration that says its unit, as the command line takes them:
    /// "15m", "15min", "1h", "2hrs", "1h30", "1h30m" or "1.5h". Unlike
    /// `parse(_:)`, it doesn't take "1:30" or a bare number, which read as
    /// times of day there.
    public static func parseWithUnit(_ text: String) -> Int64? {
        var typed = text.lowercased()
        for (long, short) in [("minutes", "m"), ("minute", "m"), ("mins", "m"), ("min", "m"), ("hours", "h"), ("hour", "h"), ("hrs", "h"), ("hr", "h")] {
            typed = typed.replacingOccurrences(of: long, with: short)
        }
        guard typed.first?.isASCIIDigit == true || typed.first == ".",
              typed.contains("h") || typed.contains("m"), !typed.contains(":"),
              let duration = parse(typed), duration > 0
        else { return nil }
        return duration
    }
}

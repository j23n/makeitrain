import Foundation

/// Entries as CSV, such as a report's, one row per entry:
///
///     date,start,end,hours,client,project,tags,note
///
/// - UTF-8 with a byte-order mark, which Excel needs to read accented
///   characters, and lines ending in CRLF.
/// - `date` is the entry's day in its own time zone; `start` and `end` are
///   ISO 8601 with the entry's own offset.
/// - `hours` has four decimals, so the column adds up to within seconds of
///   the report total; spreadsheets can't add up the ISO times.
/// - Tags are joined with `;`. A project without a client has an empty
///   client cell; an unassigned entry has empty client and project cells.
/// - A running timer is left out until it stops.
public enum CSVExport {
    private static let header = ["date", "start", "end", "hours", "client", "project", "tags", "note"]

    /// The entries in the order given, such as a report's or every entry
    /// the app has.
    public static func data(for entries: [ResolvedEntry], ledger: Ledger) -> Data {
        Data(text(for: entries, ledger: ledger).utf8)
    }

    public static func text(for entries: [ResolvedEntry], ledger: Ledger) -> String {
        var lines = [header.joined(separator: ",")]
        for resolved in entries {
            guard let end = resolved.end else { continue }
            let entry = resolved.entry
            let project = entry.projectID.flatMap { ledger.projects[$0] }
            lines.append([
                entry.day.description,
                DateTimeFormat.format(entry.start, zone: entry.timeZone),
                DateTimeFormat.format(end, zone: entry.timeZone),
                hours(resolved.duration(now: end)),
                ledger.client(forProject: entry.projectID)?.name ?? "",
                project?.name ?? "",
                entry.tags.map { $0.filter { $0 != ";" } }.joined(separator: ";"),
                entry.note,
            ].map(field).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The name for a file of entries: "Time Entries" and the days from the
    /// first entry to the last, such as "Time Entries 2025-03-04 to
    /// 2026-09-30". Nil when there are no entries.
    public static func fileName(for entries: [ResolvedEntry]) -> String? {
        guard let days = LocalDate.span(of: entries.map(\.entry.day)) else { return nil }
        let (first, last) = (days.lowerBound, days.upperBound)
        return first == last ? "Time Entries \(first)" : "Time Entries \(first) to \(last)"
    }

    /// What the `hours` column of the entries' CSV adds up to, row by row
    /// as written, such as "12.5000". A running timer is left out.
    public static func totalHours(_ entries: [ResolvedEntry]) -> String {
        decimal(entries.reduce(0) { sum, resolved in
            guard let end = resolved.end else { return sum }
            return sum + tenThousandths(resolved.duration(now: end))
        })
    }

    /// Decimal hours with four decimals, rounded half up, such as "2.4167".
    static func hours(_ milliseconds: Int64) -> String {
        decimal(tenThousandths(milliseconds))
    }

    /// Milliseconds in ten-thousandths of an hour, rounded half up.
    private static func tenThousandths(_ milliseconds: Int64) -> Int64 {
        (max(0, milliseconds) * 10000 + 1_800_000) / 3_600_000
    }

    /// Ten-thousandths of an hour as decimal hours, such as "2.4167".
    private static func decimal(_ tenThousandths: Int64) -> String {
        "\(tenThousandths / 10000).\(padded(Int(tenThousandths % 10000), 4))"
    }

    /// A field, quoted when it contains a comma, quote or line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

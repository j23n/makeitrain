import Foundation

/// A report's entries as CSV, one row per entry:
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
    public static let header = ["date", "start", "end", "hours", "client", "project", "tags", "note"]

    public static func data(for report: Report, ledger: Ledger) -> Data {
        Data(text(for: report, ledger: ledger).utf8)
    }

    public static func text(for report: Report, ledger: Ledger) -> String {
        var lines = [header.joined(separator: ",")]
        for resolved in report.entries {
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

    /// Decimal hours with four decimals, rounded half up, such as "2.4167".
    static func hours(_ milliseconds: Int64) -> String {
        let tenThousandths = (max(0, milliseconds) * 10000 + 1_800_000) / 3_600_000
        return "\(tenThousandths / 10000).\(padded(Int(tenThousandths % 10000), 4))"
    }

    /// A field, quoted when it contains a comma, quote or line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

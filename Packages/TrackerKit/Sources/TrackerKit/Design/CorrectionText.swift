import Foundation
import TrackerCore

/// The words for corrections and their fixes, as the week's list and the
/// iPhone's sheet say them.
public enum CorrectionText {
    /// What it is and when, such as "Tue 29 · Overlap 1:00".
    public static func label(_ correction: Correction, model: AppModel) -> String {
        let day = "\(Format.weekday(correction.day)) \(correction.day.day)"
        switch correction.kind {
        case let .overlap(overlap):
            return "\(day) · Overlap \(Format.duration(overlap.duration))"
        case let .ranLong(id, overnight):
            if model.ledger.entries[id]?.end == nil {
                return "\(day) · Still running"
            }
            return overnight ? "\(day) · Ran overnight" : "\(day) · Ran long"
        case .noProject:
            return "\(day) · No project"
        case .notLogged:
            return "\(day) · Not logged"
        }
    }

    /// What's wrong, as a sentence, such as "Spec runs 20 minutes into
    /// Tests".
    public static func title(_ correction: Correction, model: AppModel) -> String {
        let ledger = model.ledger
        switch correction.kind {
        case let .overlap(overlap):
            guard let earlier = ledger.entries[overlap.earlier], let later = ledger.entries[overlap.later] else {
                return "Two entries overlap"
            }
            if earlier.start == later.start {
                return "\(name(earlier, ledger)) and \(name(later, ledger)) start together"
            }
            if let earlierEnd = earlier.end, later.end.map({ earlierEnd > $0 }) ?? false {
                return "\(name(later, ledger)) sits inside \(name(earlier, ledger))"
            }
            return "\(name(earlier, ledger)) runs \(words(overlap.duration)) into \(name(later, ledger))"
        case let .ranLong(id, overnight):
            guard let entry = ledger.entries[id] else { return "An entry ran long" }
            let zone = entry.timeZone
            guard let end = entry.end else {
                return "\(name(entry, ledger)) has been running since \(Format.weekday(entry.day)) \(Format.time(entry.start, zone: zone))"
            }
            if overnight {
                let endDay = end.local(in: zone).date
                return "\(name(entry, ledger)) ran until \(Format.weekday(endDay)) \(Format.time(end, zone: zone))"
            }
            return "\(name(entry, ledger)) ran \(Format.duration(entry.start.distance(to: end)))"
        case let .noProject(id):
            guard let entry = ledger.entries[id] else { return "An entry has no project" }
            return "\(entry.note.isEmpty ? "An entry" : entry.note), \(span(entry))"
        case let .notLogged(entry):
            return "\(entry.note.isEmpty ? "An event" : entry.note), \(span(entry))"
        }
    }

    /// Why, or what the suggestion is based on, when that helps.
    public static func explanation(_ correction: Correction, model: AppModel) -> String? {
        let ledger = model.ledger
        switch correction.kind {
        case .overlap:
            return nil
        case .ranLong:
            return correction.fixes.isEmpty ? nil : "It probably ended when your day usually does."
        case .noProject:
            if case let .assign(_, projectID)? = correction.suggestion {
                return "An entry with the same note is in \(ledger.projectTitle(projectID))."
            }
            return "Choose its project, so it counts in reports."
        case let .notLogged(entry):
            return "It's in the calendar linked to \(ledger.projectTitle(entry.projectID)), so it goes there."
        }
    }

    /// What a fix does, on its button, such as "Split around it" or "End
    /// Spec at 14:40".
    public static func fixTitle(_ fix: CorrectionFix, in correction: Correction, model: AppModel) -> String {
        let ledger = model.ledger
        switch fix {
        case let .overlap(overlapFix):
            switch overlapFix {
            case .split:
                return "Split around it"
            case let .trimEarlier(id, end):
                guard let entry = ledger.entries[id] else { return "End it earlier" }
                if case let .overlap(overlap) = correction.kind, let later = ledger.entries[overlap.later],
                   let earlierEnd = entry.end, later.end.map({ earlierEnd > $0 }) ?? false {
                    return "End at \(Format.time(end, zone: entry.timeZone))"
                }
                return "End \(name(entry, ledger)) at \(Format.time(end, zone: entry.timeZone))"
            case let .trimLater(id, start):
                guard let entry = ledger.entries[id] else { return "Start it later" }
                return "Start \(name(entry, ledger)) at \(Format.time(start, zone: entry.timeZone))"
            }
        case let .end(id, time):
            let zone = ledger.entries[id]?.timeZone ?? model.environment.timeZone()
            return "End at \(Format.time(time, zone: zone))"
        case let .assign(_, projectID):
            return "Assign to \(ledger.projects[projectID]?.name ?? "it")"
        case .add:
            return "Log it"
        }
    }

    /// "1 suggestion", in words up to ten, as in "Accept the four with a
    /// suggestion".
    public static func number(_ count: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return count < words.count ? words[count] : "\(count)"
    }

    /// An entry's note, or its project's name.
    static func name(_ entry: TimeEntry, _ ledger: Ledger) -> String {
        entry.note.isEmpty ? ledger.projectTitle(entry.projectID) : entry.note
    }

    /// "12:30–12:55".
    static func span(_ entry: TimeEntry) -> String {
        let zone = entry.timeZone
        return "\(Format.time(entry.start, zone: zone))–\(entry.end.map { Format.time($0, zone: zone) } ?? "now")"
    }

    /// "20 minutes" under an hour, and "1:05" from an hour.
    static func words(_ milliseconds: Int64) -> String {
        let minutes = Int(milliseconds / 60000)
        if minutes < 60 {
            return minutes == 1 ? "a minute" : "\(minutes) minutes"
        }
        return Format.duration(milliseconds)
    }
}

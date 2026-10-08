import SwiftUI
import TrackerCore

/// A CSV file picked for import, with what importing it adds.
public struct ImportRequest: Identifiable {
    public let id = UUID()
    public let fileName: String
    public let plan: CSVImport.Plan

    public init(fileName: String, plan: CSVImport.Plan) {
        self.fileName = fileName
        self.plan = plan
    }
}

/// What importing a CSV file adds, as sections of a form: the entries and
/// the days they're on, new clients and projects, rows already there, and
/// rows that can't be read.
public struct ImportSummary: View {
    let plan: CSVImport.Plan
    let ledger: Ledger

    /// Rows that can't be read shown before "and N more".
    static let shownProblems = 50

    public init(plan: CSVImport.Plan, ledger: Ledger) {
        self.plan = plan
        self.ledger = ledger
    }

    public var body: some View {
        Section {
            LabeledContent("Entries", value: "\(plan.entries.count)")
            if let days = plan.days {
                LabeledContent("Days", value: Format.days(days))
                LabeledContent("Time", value: Format.duration(total))
            }
            if !plan.clients.isEmpty {
                LabeledContent("New clients", value: plan.clients.map(\.name).joined(separator: ", "))
            }
            if !plan.projects.isEmpty {
                LabeledContent("New projects", value: plan.projects.map(title).joined(separator: ", "))
            }
        } footer: {
            if !notes.isEmpty {
                Text(notes.joined(separator: " "))
                    .foregroundStyle(.secondary)
            }
        }
        if !plan.problems.isEmpty {
            Section(plan.problems.count == 1 ? "A Row Can't Be Read" : "\(plan.problems.count) Rows Can't Be Read") {
                ForEach(plan.problems.prefix(Self.shownProblems), id: \.self) { problem in
                    LabeledContent("Line \(problem.line)", value: problem.message)
                }
                if plan.problems.count > Self.shownProblems {
                    Text("and \(plan.problems.count - Self.shownProblems) more")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var total: Int64 {
        var total: Int64 = 0
        for entry in plan.entries {
            if let end = entry.end {
                total += entry.start.distance(to: end)
            }
        }
        return total
    }

    private var notes: [String] {
        var notes: [String] = []
        if plan.alreadyThere > 0 {
            notes.append(plan.alreadyThere == 1
                ? "1 entry already exists and is skipped."
                : "\(plan.alreadyThere) entries already exist and are skipped.")
        }
        if plan.placed > 0 {
            notes.append(plan.placed == 1
                ? "1 entry has no times. It starts at 9:00."
                : "\(plan.placed) entries have no times. They start at 9:00, one after another.")
        }
        if plan.entries.isEmpty, plan.alreadyThere == 0 {
            notes.append("Nothing to import.")
        }
        return notes
    }

    /// A new project as pickers show it, such as "Acme › Website".
    private func title(_ project: Project) -> String {
        let client = project.clientID.flatMap { id in plan.clients.first { $0.id == id } ?? ledger.clients[id] }
        return client.map { "\($0.name) › \(project.name)" } ?? project.name
    }
}

/// What importing calendar events adds, as sections of a form: the entries,
/// the days they're on and the time per project, the events left out and
/// why, and a switch to bring back entries that were imported and deleted.
public struct CalendarImportSummary: View {
    let plan: CalendarImport.Plan
    let ledger: Ledger
    @Binding var includingDeleted: Bool

    public init(plan: CalendarImport.Plan, ledger: Ledger, includingDeleted: Binding<Bool>) {
        self.plan = plan
        self.ledger = ledger
        _includingDeleted = includingDeleted
    }

    public var body: some View {
        Section {
            LabeledContent("Entries", value: "\(plan.entries.count)")
            if let days = plan.days {
                LabeledContent("Days", value: Format.days(days))
                LabeledContent("Time", value: Format.duration(projects.reduce(0) { $0 + $1.total }))
            }
        } footer: {
            if !notes.isEmpty {
                Text(notes.joined(separator: " "))
                    .foregroundStyle(.secondary)
            }
        }
        if !projects.isEmpty {
            Section("Projects") {
                ForEach(projects) { project in
                    LabeledContent {
                        Text("\(project.count == 1 ? "1 entry" : "\(project.count) entries"), \(Format.duration(project.total))")
                    } label: {
                        ProjectLabel(ledger: ledger, projectID: project.id)
                    }
                }
            }
        }
        if plan.deleted > 0 {
            Section {
                Toggle(plan.deleted == 1 ? "Import deleted entry again" : "Import \(plan.deleted) deleted entries again", isOn: $includingDeleted)
            } footer: {
                Text(plan.deleted == 1
                    ? "1 event was imported before, then its entry was deleted."
                    : "\(plan.deleted) events were imported before, then their entries were deleted.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Each project's new entries and their time.
    struct ProjectTotal: Identifiable {
        let id: UUID?
        var count = 0
        var total: Int64 = 0
    }

    private var projects: [ProjectTotal] {
        var totals: [UUID?: ProjectTotal] = [:]
        for entry in plan.entries {
            totals[entry.projectID, default: ProjectTotal(id: entry.projectID)].count += 1
            if let end = entry.end {
                totals[entry.projectID, default: ProjectTotal(id: entry.projectID)].total += entry.start.distance(to: end)
            }
        }
        return totals.values.sorted { ledger.projectTitle($0.id).lowercased() < ledger.projectTitle($1.id).lowercased() }
    }

    private var notes: [String] {
        var notes: [String] = []
        if plan.alreadyThere > 0 {
            notes.append(plan.alreadyThere == 1 ? "1 event is already imported." : "\(plan.alreadyThere) events are already imported.")
        }
        for reason in CalendarImport.Skip.allCases {
            if let count = plan.skipped[reason], count > 0 {
                notes.append(Self.note(reason, count: count))
            }
        }
        if plan.entries.isEmpty, notes.isEmpty, plan.deleted == 0 {
            notes.append("No events on these days.")
        }
        return notes
    }

    /// Why some events are left out, such as "2 all-day events are left out."
    static func note(_ reason: CalendarImport.Skip, count: Int) -> String {
        let one = count == 1
        let events: String
        switch reason {
        case .allDay:
            events = one ? "1 all-day event is" : "\(count) all-day events are"
        case .cancelled:
            events = one ? "1 cancelled event is" : "\(count) cancelled events are"
        case .declined:
            events = one ? "1 declined event is" : "\(count) declined events are"
        case .free:
            events = one ? "1 event shown as free or out of office is" : "\(count) events shown as free or out of office are"
        case .noTime:
            events = one ? "1 event that takes no time is" : "\(count) events that take no time are"
        case .tooLong:
            events = one ? "1 event longer than a day is" : "\(count) events longer than a day are"
        case .notOver:
            events = one ? "1 event that hasn't ended yet is" : "\(count) events that haven't ended yet are"
        }
        return events + " left out."
    }
}

/// A project's color and title, such as "● Acme › Website".
private struct ProjectLabel: View {
    let ledger: Ledger
    let projectID: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ProjectDot(ledger: ledger, projectID: projectID)
            Text(ledger.projectTitle(projectID))
                .lineLimit(1)
                .foregroundStyle(projectID == nil ? .secondary : .primary)
        }
    }
}

/// A project's color as a dot, or a ring for no project, as pickers show
/// "No Project". The ring keeps unassigned entries apart from a gray
/// project. The dot grows with Dynamic Type, like the text beside it.
private struct ProjectDot: View {
    let color: RGBA?
    @ScaledMetric private var size: CGFloat = 8

    init(ledger: Ledger, projectID: UUID?) {
        color = projectID.map { ledger.tint(ofProject: $0).base }
    }

    var body: some View {
        Group {
            if let color {
                Circle()
                    .fill(Color(light: color, dark: color))
            } else {
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Calendar Import Summary") {
    let model = PreviewData.model()
    let plan = model.calendarImportPlan(from: LocalDate(year: 2026, month: 9, day: 21), through: LocalDate(year: 2026, month: 9, day: 23))
    return Form {
        CalendarImportSummary(plan: plan, ledger: model.ledger, includingDeleted: .constant(false))
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 460)
}
#endif

#if DEBUG
#Preview("Import Summary") {
    let csv = """
    Date,Client,Project,Notes,Hours
    2026-09-24,Acme,Website,Design review,1.5
    2026-09-24,Initech,Consulting,Kickoff,2
    2026-09-25,,Internal,Admin,0.5
    2026-09-25,,Internal,,banana
    """
    let plan = try! CSVImport.plan(Data(csv.utf8), into: PreviewData.ledger, timeZone: "Europe/Berlin", now: PreviewData.now)
    return Form {
        ImportSummary(plan: plan, ledger: PreviewData.ledger)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 420)
}
#endif

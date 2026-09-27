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
                ? "1 entry is already there and is skipped."
                : "\(plan.alreadyThere) entries are already there and are skipped.")
        }
        if plan.placed > 0 {
            notes.append(plan.placed == 1
                ? "1 entry has a duration but no times, so it starts at 9:00."
                : "\(plan.placed) entries have durations but no times, so they're placed one after another from 9:00.")
        }
        if plan.entries.isEmpty, plan.alreadyThere == 0 {
            notes.append("There's nothing to import.")
        }
        return notes
    }

    /// A new project as pickers show it, such as "Acme › Website".
    private func title(_ project: Project) -> String {
        let client = project.clientID.flatMap { id in plan.clients.first { $0.id == id } ?? ledger.clients[id] }
        return client.map { "\($0.name) › \(project.name)" } ?? project.name
    }
}

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

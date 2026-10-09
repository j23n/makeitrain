import SwiftUI
import TrackerCore
import UniformTypeIdentifiers

/// A CSV file picked for import, with what importing it adds.
struct ImportRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let plan: CSVImport.Plan
}

extension View {
    /// Picks a CSV file to import while `isPresented` is true, then shows
    /// what importing it adds, or why it can't be read. The import undoes
    /// in `undoManager`, the presenting window's.
    public func csvImporter(isPresented: Binding<Bool>, model: AppModel, undoManager: UndoManager?) -> some View {
        modifier(CSVImporter(isPresented: isPresented, model: model, undoManager: undoManager))
    }
}

/// The file importer for CSV files, the sheet with what the picked file
/// adds, and the alert for a file that can't be read.
private struct CSVImporter: ViewModifier {
    @Binding var isPresented: Bool
    let model: AppModel
    let undoManager: UndoManager?
    @State private var request: ImportRequest?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                do {
                    request = try model.importRequest(forFileAt: result.get())
                } catch {
                    failure = error.localizedDescription
                }
            }
            .sheet(item: $request) { request in
                ImportSheet(model: model, request: request, undoManager: undoManager)
            }
            .alert("Couldn't Import the File", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }
}

/// Shows what importing a CSV file adds, and adds it.
struct ImportSheet: View {
    let model: AppModel
    let request: ImportRequest
    /// The presenting window's, so the import undoes there.
    let undoManager: UndoManager?

    var body: some View {
        ImportSheetFrame(title: title, count: request.plan.entries.count, height: 460, model: model) {
            model.importEntries(request.plan, undoManager: undoManager)
        } content: {
            ImportSummary(plan: request.plan, ledger: model.ledger)
        }
    }

    private var title: String {
        #if os(macOS)
        return "Import \u{201C}\(request.fileName)\u{201D}"
        #else
        return request.fileName
        #endif
    }
}

/// Imports the events of linked calendars that start on some days, after
/// showing what that adds.
public struct CalendarImportSheet: View {
    let model: AppModel
    /// The presenting window's, so the import undoes there.
    let undoManager: UndoManager?
    @State private var first: LocalDate
    @State private var last: LocalDate
    @State private var includingDeleted = false

    /// Starts with this week up to today.
    public init(model: AppModel, undoManager: UndoManager?) {
        self.model = model
        self.undoManager = undoManager
        let today = model.today
        _first = State(initialValue: today.startOfWeek(firstWeekday: model.firstWeekday))
        _last = State(initialValue: today)
    }

    public var body: some View {
        let plan = model.calendarImportPlan(from: first, through: last, includingDeleted: includingDeleted)
        ImportSheetFrame(title: title, count: plan.entries.count, height: 540, model: model) {
            model.importEvents(plan, undoManager: undoManager)
        } content: {
            Section {
                DatePicker("From", selection: pickerDate($first), in: ...last.pickerDate, displayedComponents: .date)
                DatePicker("Through", selection: pickerDate($last), in: first.pickerDate..., displayedComponents: .date)
            }
            if model.hasLinkedCalendars {
                CalendarImportSummary(plan: plan, ledger: model.ledger, includingDeleted: $includingDeleted)
            } else {
                Section {
                    #if os(macOS)
                    Text("No project has a calendar. Link one on a project's page.")
                        .foregroundStyle(.secondary)
                    #else
                    Text("No project has a calendar. Link one in Settings or on a project's page.")
                        .foregroundStyle(Theme.text2)
                    #endif
                }
            }
        }
        .onAppear {
            model.refreshCalendars()
        }
    }

    private var title: String {
        #if os(macOS)
        return "Import Calendar Events"
        #else
        return "Import Events"
        #endif
    }

    private func pickerDate(_ day: Binding<LocalDate>) -> Binding<Date> {
        Binding(
            get: { day.wrappedValue.pickerDate },
            set: { day.wrappedValue = LocalDate(pickerDate: $0) }
        )
    }
}

/// An import's sheet around a form with what it adds, with Cancel and
/// Import: on the Mac a title over the form and the buttons under it, and
/// on iPhone and iPad the buttons in the sheet's bar.
private struct ImportSheetFrame<Content: View>: View {
    let title: String
    /// How many entries the import adds.
    let count: Int
    /// The sheet's height on the Mac.
    let height: CGFloat
    let model: AppModel
    /// Adds what the import found, when Import is chosen.
    let perform: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], 20)
            Form {
                content
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(count == 1 ? "Import 1 Entry" : "Import \(count) Entries") {
                    perform()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0 || model.isReadOnly)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 540, height: height)
        #else
        NavigationStack {
            Form {
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        perform()
                        dismiss()
                    }
                    .disabled(count == 0 || model.isReadOnly)
                }
            }
        }
        #endif
    }
}

/// What importing a CSV file adds, as sections of a form: the entries and
/// the days they're on, new clients and projects, rows already there, and
/// rows that can't be read.
struct ImportSummary: View {
    let plan: CSVImport.Plan
    let ledger: Ledger

    /// Rows that can't be read shown before "and N more".
    static let shownProblems = 50

    var body: some View {
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
struct CalendarImportSummary: View {
    let plan: CalendarImport.Plan
    let ledger: Ledger
    @Binding var includingDeleted: Bool

    var body: some View {
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

#Preview("Import") {
    let csv = """
    start,end,client,project,tags,note
    2026-09-24T09:00:00+02:00,2026-09-24T10:30:00+02:00,Acme,Website redesign,design,Review
    2026-09-24T11:00:00+02:00,2026-09-24T12:00:00+02:00,Initech,Consulting,,Kickoff
    2026-09-23T09:00:00+02:00,2026-09-23T10:30:00+02:00,Acme,Website redesign,client-call,Kickoff with the new team
    """
    let model = PreviewData.model()
    let plan = try! model.importPlan(for: Data(csv.utf8))
    return ImportSheet(model: model, request: ImportRequest(fileName: "toggl-september.csv", plan: plan), undoManager: nil)
}

#Preview("Import Events") {
    CalendarImportSheet(model: PreviewData.model(), undoManager: nil)
}

#Preview("Nothing Linked") {
    CalendarImportSheet(model: PreviewData.model(calendarLinks: []), undoManager: nil)
}
#endif

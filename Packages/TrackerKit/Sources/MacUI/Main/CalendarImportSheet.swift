#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Imports the events of linked calendars that start on some days, after
/// showing what that adds.
struct CalendarImportSheet: View {
    let model: AppModel
    /// The main window's, so the import undoes there.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var first: LocalDate
    @State private var last: LocalDate
    @State private var includingDeleted = false

    /// Starts with this week up to today.
    init(model: AppModel, undoManager: UndoManager?) {
        self.model = model
        self.undoManager = undoManager
        let today = model.today
        _first = State(initialValue: today.startOfWeek(firstWeekday: model.firstWeekday))
        _last = State(initialValue: today)
    }

    var body: some View {
        let plan = model.calendarImportPlan(from: first, through: last, includingDeleted: includingDeleted)
        let count = plan.entries.count
        VStack(spacing: 0) {
            Text("Import Calendar Events")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], 20)
            Form {
                Section {
                    DatePicker("From", selection: pickerDate($first), in: ...last.pickerDate, displayedComponents: .date)
                    DatePicker("Through", selection: pickerDate($last), in: first.pickerDate..., displayedComponents: .date)
                }
                if model.hasLinkedCalendars {
                    CalendarImportSummary(plan: plan, ledger: model.ledger, includingDeleted: $includingDeleted)
                } else {
                    Section {
                        Text("No calendar is linked to a project yet. Link each client's calendar to one of their projects in Settings › Calendars.")
                            .foregroundStyle(.secondary)
                        SettingsLink {
                            Text("Open Settings…")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(count == 1 ? "Import 1 Entry" : "Import \(count) Entries") {
                    model.importEvents(plan, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0 || model.isReadOnly)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 540, height: 540)
        .onAppear {
            model.refreshCalendars()
        }
    }

    private func pickerDate(_ day: Binding<LocalDate>) -> Binding<Date> {
        Binding(
            get: { day.wrappedValue.pickerDate },
            set: { day.wrappedValue = LocalDate(pickerDate: $0) }
        )
    }
}

#if DEBUG
#Preview("Import Events") {
    CalendarImportSheet(model: PreviewData.model(), undoManager: nil)
}

#Preview("Nothing Linked") {
    CalendarImportSheet(model: PreviewData.model(calendarLinks: []), undoManager: nil)
}
#endif
#endif

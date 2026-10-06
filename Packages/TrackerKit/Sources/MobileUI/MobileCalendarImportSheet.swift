#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Imports the events of linked calendars that start on some days, after
/// showing what that adds.
struct MobileCalendarImportSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var first: LocalDate
    @State private var last: LocalDate
    @State private var includingDeleted = false

    /// Starts with this week up to today.
    init(model: AppModel) {
        self.model = model
        let today = model.today
        _first = State(initialValue: today.startOfWeek(firstWeekday: model.firstWeekday))
        _last = State(initialValue: today)
    }

    var body: some View {
        let plan = model.calendarImportPlan(from: first, through: last, includingDeleted: includingDeleted)
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: pickerDate($first), in: ...last.pickerDate, displayedComponents: .date)
                    DatePicker("Through", selection: pickerDate($last), in: first.pickerDate..., displayedComponents: .date)
                }
                if model.hasLinkedCalendars {
                    CalendarImportSummary(plan: plan, ledger: model.ledger, includingDeleted: $includingDeleted)
                } else {
                    Section {
                        Text("No project has a calendar. Link one in Settings or on a project's page.")
                            .foregroundStyle(Theme.text2)
                    }
                }
            }
            .navigationTitle("Import Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        model.importEvents(plan, undoManager: undoManager)
                        dismiss()
                    }
                    .disabled(plan.entries.isEmpty || model.isReadOnly)
                }
            }
        }
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
    MobileCalendarImportSheet(model: PreviewData.model())
}
#endif
#endif

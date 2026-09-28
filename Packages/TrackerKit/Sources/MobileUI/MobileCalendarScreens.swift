#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// Which of this device's calendars have their events imported, and for
/// which project: one project per client's calendar.
struct MobileCalendarsScreen: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                switch model.calendarAccess {
                case .notDetermined:
                    Button("Allow Access to Calendars") {
                        Task { await model.requestCalendarAccess() }
                    }
                case .denied:
                    Text("Time Tracker isn't allowed to read your calendars.")
                    Button("Allow Access in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                case .restricted:
                    Text("Reading calendars isn't allowed on this device.")
                case .granted:
                    if model.calendars.isEmpty {
                        Text("This device has no calendars yet. Add a client's account in Settings › Apps › Calendar › Calendar Accounts, or subscribe to their calendar's link.")
                    }
                }
            } footer: {
                Text("Link each client's calendar to one of their projects. Importing then adds the calendar's events as entries for that project, with each event's title as the note. The links are kept on this device.")
            }
            if model.calendarAccess == .granted {
                ForEach(accounts, id: \.self) { account in
                    Section(account.isEmpty ? "Other" : account) {
                        ForEach(calendars(in: account)) { calendar in
                            ProjectPicker(ledger: model.ledger, selection: project(of: calendar), title: calendar.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refreshCalendars()
        }
    }

    /// The accounts with calendars, such as "iCloud" or a work address.
    private var accounts: [String] {
        Set(model.calendars.map(\.account)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func calendars(in account: String) -> [CalendarInfo] {
        model.calendars
            .filter { $0.account == account }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func project(of calendar: CalendarInfo) -> Binding<UUID?> {
        Binding(
            get: { model.linkedProject(of: calendar.id) },
            set: { model.link(calendar, to: $0) }
        )
    }
}

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
                        NavigationLink("Link Calendars") {
                            MobileCalendarsScreen(model: model)
                        }
                    } footer: {
                        Text("No calendar is linked to a project yet.")
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
#Preview("Calendars") {
    NavigationStack {
        MobileCalendarsScreen(model: PreviewData.model())
    }
}

#Preview("Calendars, Not Asked Yet") {
    NavigationStack {
        MobileCalendarsScreen(model: PreviewData.model(calendarAccess: .notDetermined, calendarLinks: []))
    }
}

#Preview("Import Events") {
    MobileCalendarImportSheet(model: PreviewData.model())
}
#endif
#endif

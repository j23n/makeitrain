#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// Which of this Mac's calendars have their events imported, and for which
/// project: one project per client's calendar.
struct CalendarSettings: View {
    let model: AppModel

    static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    var body: some View {
        Form {
            Section {
                Text("Link each client's calendar to one of their projects. File › Import Calendar Events… then adds the calendar's events as entries for that project, with each event's title as the note. The links are kept on this Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch model.calendarAccess {
                case .notDetermined:
                    Button("Allow Access to Calendars…") {
                        Task { await model.requestCalendarAccess() }
                    }
                case .denied:
                    Text("Time Tracker isn't allowed to read your calendars. Allow it in System Settings › Privacy & Security › Calendars.")
                    Button("Open Privacy & Security") {
                        NSWorkspace.shared.open(Self.privacySettings)
                    }
                case .restricted:
                    Text("Reading calendars isn't allowed on this Mac.")
                case .granted:
                    if model.calendars.isEmpty {
                        Text("This Mac has no calendars yet. Add a client's account in System Settings › Internet Accounts, or subscribe to their calendar's link in Calendar with File › New Calendar Subscription.")
                    }
                }
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
        .formStyle(.grouped)
        .frame(height: 440)
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

#if DEBUG
#Preview("Calendars") {
    CalendarSettings(model: PreviewData.model())
        .frame(width: 500)
}

#Preview("Not Asked Yet") {
    CalendarSettings(model: PreviewData.model(calendarAccess: .notDetermined, calendarLinks: []))
        .frame(width: 500)
}

#Preview("Access Denied") {
    CalendarSettings(model: PreviewData.model(calendarAccess: .denied))
        .frame(width: 500)
}
#endif
#endif

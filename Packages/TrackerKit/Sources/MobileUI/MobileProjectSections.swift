#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

// The parts of a project's settings beyond its name and client: its GitHub
// repositories, and the calendar on this device its events come from.

/// The GitHub repositories that tags like "#123" refer to.
struct MobileRepositoriesSection: View {
    let model: AppModel
    let project: Project
    @Environment(\.undoManager) private var undoManager
    @State private var newRepository = ""
    @State private var invalid = false

    /// A repository as the project stores it, and read.
    struct Item: Identifiable {
        let index: Int
        let address: String
        let repository: GitHub.Repository

        var id: String { address }
    }

    var body: some View {
        let repositories = project.repositories.enumerated().compactMap { index, address in
            GitHub.Repository(address).map { Item(index: index, address: address, repository: $0) }
        }
        Section {
            ForEach(repositories) { item in
                if let url = URL(string: item.address) {
                    Link(destination: url) {
                        HStack {
                            Text(item.repository.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if item.index == 0, repositories.count > 1 {
                                Text("#123")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if item.index > 0 {
                            Button {
                                makeFirst(item)
                            } label: {
                                Label("Make First", systemImage: "arrow.up")
                            }
                            .tint(.accentColor)
                        }
                    }
                    .contextMenu {
                        if item.index > 0 {
                            Button {
                                makeFirst(item)
                            } label: {
                                Label("Make First", systemImage: "arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            model.removeRepository(item.address, fromProject: project.id, undoManager: undoManager)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    model.removeRepository(repositories[offset].address, fromProject: project.id, undoManager: undoManager)
                }
            }
            HStack {
                TextField("owner/repo or URL", text: $newRepository)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(add)
                    .onChange(of: newRepository) { _, _ in
                        invalid = false
                    }
                Button("Add", action: add)
                    .disabled(newRepository.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if invalid {
                Text("Not a GitHub repository. Use owner/repo or a URL.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("GitHub")
        } footer: {
            Text(repositories.count > 1
                ? "#123 refers to an issue in the first repository. Swipe right to make another one first."
                : "#123 refers to an issue in this repository.")
        }
    }

    private func makeFirst(_ item: Item) {
        model.makeFirstRepository(item.address, ofProject: project.id, undoManager: undoManager)
    }

    private func add() {
        let text = newRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if model.addRepository(text, toProject: project.id, undoManager: undoManager) {
            newRepository = ""
        } else {
            invalid = true
        }
    }
}

/// The calendar on this device whose events are imported for the project.
struct MobileProjectCalendarSection: View {
    let model: AppModel
    let project: Project
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow Access to Calendars") {
                    Task { await model.requestCalendarAccess() }
                }
            case .denied:
                Button("Allow Access in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            case .restricted:
                Text("Calendar access is restricted on this device.")
                    .foregroundStyle(.secondary)
            case .granted:
                Picker("Calendar", selection: Binding(
                    get: { model.linkedCalendar(ofProject: project.id)?.id },
                    set: { model.setCalendar($0, forProject: project.id) }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(accounts, id: \.self) { account in
                        Section(account.isEmpty ? "Other" : account) {
                            ForEach(calendars(in: account)) { calendar in
                                Text(label(for: calendar)).tag(String?.some(calendar.id))
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Calendar on This Device")
        }
        .onAppear {
            model.refreshCalendars()
        }
    }

    /// The calendars' accounts, in the order of the calendars, which the
    /// model sorts by account.
    private var accounts: [String] {
        var seen: Set<String> = []
        return model.calendars.map(\.account).filter { seen.insert($0).inserted }
    }

    private func calendars(in account: String) -> [CalendarInfo] {
        model.calendars.filter { $0.account == account }
    }

    /// A calendar's title, and the project it's linked to if that's another.
    private func label(for calendar: CalendarInfo) -> String {
        guard let other = model.linkedProject(of: calendar.id), other != project.id else { return calendar.title }
        return "\(calendar.title) (\(model.ledger.projectTitle(other)))"
    }
}
#endif

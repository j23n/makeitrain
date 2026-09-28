#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

// The parts of a project's form beyond its name and client: its tags, its
// GitHub repositories, and the calendar on this device its events come from.

/// A project's tags, with the ones that refer to issues linked.
struct MobileProjectTagsSection: View {
    let model: AppModel
    let project: Project

    var body: some View {
        let tags = model.ledger.tags(ofProject: project.id)
        Section {
            if tags.isEmpty {
                Text("None yet")
                    .foregroundStyle(.secondary)
            } else {
                TagList(tags: tags, links: model.ledger.issueLinks(tags: tags, projectID: project.id), wraps: true)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Each project has its own tags: the ones on its entries.")
        }
    }
}

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
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    model.removeRepository(repositories[offset].address, fromProject: project.id, undoManager: undoManager)
                }
            }
            HStack {
                TextField("owner/name or its address", text: $newRepository)
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
                Text("That isn't a GitHub repository. Write it as owner/name, or paste its address.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("GitHub")
        } footer: {
            Text(repositories.count > 1
                ? "A tag like #123 opens issue or pull request 123 in the first repository. For another one, write its name first, like \(repositories[1].repository.name)#123."
                : "A tag like #123 opens issue or pull request 123 in this repository.")
        }
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
                Text("Reading calendars isn't allowed on this device.")
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
        } footer: {
            Text("Settings › Import Calendar Events… adds the calendar's events to this project, with each event's title as the note. Each iPhone and Mac keeps its own calendar links.")
        }
        .onAppear {
            model.refreshCalendars()
        }
    }

    private var accounts: [String] {
        Set(model.calendars.map(\.account)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func calendars(in account: String) -> [CalendarInfo] {
        model.calendars
            .filter { $0.account == account }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// A calendar's title, and the project it's linked to if that's another.
    private func label(for calendar: CalendarInfo) -> String {
        guard let other = model.linkedProject(of: calendar.id), other != project.id else { return calendar.title }
        return "\(calendar.title) (\(model.ledger.projectTitle(other)))"
    }
}
#endif

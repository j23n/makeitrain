#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

// The parts of a project's settings beyond its name and client: its GitHub
// repositories, and the calendar on this Mac its events come from.

/// The GitHub repositories that tags like "#123" refer to.
struct RepositoriesSection: View {
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
                let index = item.index
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.secondary)
                    Text(item.repository.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if index == 0, repositories.count > 1 {
                        Text("#123")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Tags like #123 refer to this repository")
                    }
                    Spacer()
                    if let url = URL(string: item.address) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Open \(item.repository.title) on GitHub")
                    }
                    Button {
                        model.removeRepository(item.address, fromProject: project.id, undoManager: undoManager)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(item.repository.title)")
                }
                .contextMenu {
                    if index > 0 {
                        Button("Use for Tags Like #123") {
                            model.makeFirstRepository(item.address, ofProject: project.id, undoManager: undoManager)
                        }
                    }
                }
            }
            HStack {
                TextField("Repository", text: $newRepository, prompt: Text("owner/name or its address"))
                    .labelsHidden()
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
                ? "A tag like #123 opens issue or pull request 123 in the first repository; for another one, write its name first, like \(repositories[1].repository.name)#123. Right-click a repository to make it the first: the project's tags like #123 are rewritten so they keep their issues."
                : "A tag like #123 opens issue or pull request 123 in this repository.")
                .foregroundStyle(.secondary)
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

/// The calendar on this Mac whose events are imported for the project.
struct ProjectCalendarSection: View {
    let model: AppModel
    let project: Project

    static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    var body: some View {
        Section {
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow Access to Calendars…") {
                    Task { await model.requestCalendarAccess() }
                }
            case .denied:
                Text("Time Tracker isn't allowed to read your calendars.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security") {
                    NSWorkspace.shared.open(Self.privacySettings)
                }
            case .restricted:
                Text("Reading calendars isn't allowed on this Mac.")
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
            Text("Calendar on This Mac")
        } footer: {
            Text("File › Import Calendar Events… adds the calendar's events to this project, with each event's title as the note. Each Mac and iPhone keeps its own calendar links.")
                .foregroundStyle(.secondary)
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

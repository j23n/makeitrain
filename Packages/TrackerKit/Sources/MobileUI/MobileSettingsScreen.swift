#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// iCloud, the first day of the week, and clients and projects.
struct MobileSettingsScreen: View {
    @Bindable var model: AppModel
    @State private var switching = false
    @State private var switchError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Keep Data in iCloud Drive", isOn: iCloudBinding)
                        .disabled(switching || (!model.isICloudAvailable && model.storage == .local))
                } footer: {
                    Text(storageExplanation)
                }

                Section {
                    NavigationLink("Clients & Projects") {
                        MobileProjectsScreen(model: model)
                    }
                }

                Section("Reports") {
                    Picker("First Day of the Week", selection: $model.firstWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Couldn't Switch Storage", isPresented: Binding(get: { switchError != nil }, set: { if !$0 { switchError = nil } })) {
                Button("OK") { switchError = nil }
            } message: {
                Text(switchError ?? "")
            }
        }
    }

    private var iCloudBinding: Binding<Bool> {
        Binding(
            get: { model.storage == .iCloud },
            set: { on in
                switching = true
                Task {
                    do {
                        try await model.switchStorage(to: on ? .iCloud : .local)
                    } catch {
                        switchError = error.localizedDescription
                    }
                    switching = false
                }
            }
        )
    }

    private var storageExplanation: String {
        switch model.storage {
        case .iCloud:
            "Your data syncs through iCloud Drive with your other devices. Turning this off copies it to this device and leaves iCloud as it is."
        case .local:
            model.isICloudAvailable
                ? "Your data stays on this device. Turning iCloud on merges it with any data already in iCloud Drive."
                : "Your data stays on this device. Sign in to iCloud to sync it."
        }
    }
}

/// Clients and projects: add, rename, archive and delete them.
struct MobileProjectsScreen: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var showArchived = false
    @State private var adding: Adding?
    @State private var newName = ""

    enum ProjectsDestination: Hashable {
        case client(UUID)
        case project(UUID)
    }

    enum Adding {
        case client, project
    }

    var body: some View {
        List {
            Section("Clients") {
                ForEach(clients) { client in
                    NavigationLink(value: ProjectsDestination.client(client.id)) {
                        HStack {
                            Text(client.name)
                            if client.archived {
                                Spacer()
                                Text("Archived")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Add Client") {
                    newName = ""
                    adding = .client
                }
                .disabled(model.isReadOnly)
            }
            Section("Projects") {
                ForEach(projects) { project in
                    NavigationLink(value: ProjectsDestination.project(project.id)) {
                        HStack {
                            ProjectLabel(ledger: model.ledger, projectID: project.id)
                            if model.ledger.isArchived(project: project.id) {
                                Spacer()
                                Text("Archived")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Add Project") {
                    newName = ""
                    adding = .project
                }
                .disabled(model.isReadOnly)
            }
        }
        .navigationTitle("Clients & Projects")
        .navigationDestination(for: ProjectsDestination.self) { destination in
            switch destination {
            case .client(let id):
                MobileClientForm(model: model, id: id)
            case .project(let id):
                MobileProjectForm(model: model, id: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Show Archived", isOn: $showArchived)
                    .toggleStyle(.button)
            }
        }
        .alert(
            adding == .project ? "New Project" : "New Client",
            isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } }),
            presenting: adding
        ) { kind in
            TextField("Name", text: $newName)
            Button("Add") {
                add(kind)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func add(_ kind: Adding) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch kind {
        case .client:
            model.addClient(named: name, undoManager: undoManager)
        case .project:
            model.addProject(named: name, client: nil, color: ProjectColors.next(in: model.ledger), undoManager: undoManager)
        }
    }

    private var clients: [Client] {
        model.ledger.liveClients().filter { showArchived || !$0.archived }
    }

    private var projects: [Project] {
        model.ledger.projects.values
            .filter { !$0.isDeleted && (showArchived || !model.ledger.isArchived(project: $0.id)) }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
    }
}

struct MobileClientForm: View {
    let model: AppModel
    let id: UUID
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        if let client = model.ledger.clients[id], !client.isDeleted {
            Form {
                Section {
                    CommitField(title: "Name", value: client.name) { name in
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        model.updateClient(id, actionName: "Rename Client", undoManager: undoManager) { $0.name = trimmed }
                    }
                    Toggle("Archived", isOn: Binding(
                        get: { client.archived },
                        set: { archived in setArchived(archived) }
                    ))
                } footer: {
                    Text("An archived client and its projects are hidden when starting timers, but stay in reports.")
                }
                Section {
                    Button("Delete Client", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .disabled(model.isReadOnly)
            .navigationTitle(client.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete “\(client.name)” and its projects?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Client", role: .destructive) {
                    do {
                        try model.deleteClient(id, undoManager: undoManager)
                        dismiss()
                    } catch {
                        cantDelete = true
                    }
                }
            }
            .alert("“\(client.name)” Has Logged Time", isPresented: $cantDelete) {
                Button("Archive") { setArchived(true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A client whose projects have entries can't be deleted. Archive it instead, or merge it on a Mac.")
            }
        } else {
            ContentUnavailableView("Client Deleted", systemImage: "trash")
        }
    }

    private func setArchived(_ archived: Bool) {
        model.updateClient(id, actionName: archived ? "Archive Client" : "Unarchive Client", undoManager: undoManager) {
            $0.archived = archived
        }
    }
}

struct MobileProjectForm: View {
    let model: AppModel
    let id: UUID
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        if let project = model.ledger.projects[id], !project.isDeleted {
            Form {
                Section {
                    CommitField(title: "Name", value: project.name) { name in
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        update("Rename Project") { $0.name = trimmed }
                    }
                    Picker("Client", selection: Binding(
                        get: { project.clientID },
                        set: { clientID in update("Change Client") { $0.clientID = clientID } }
                    )) {
                        Text("No client").tag(UUID?.none)
                        ForEach(model.ledger.liveClients().filter { !$0.archived || $0.id == project.clientID }) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                    }
                    Toggle("Archived", isOn: Binding(
                        get: { project.archived },
                        set: { archived in setArchived(archived) }
                    ))
                }
                Section("Color") {
                    HStack {
                        ForEach(ProjectColors.palette, id: \.self) { hex in
                            Button {
                                update("Change Color") { $0.color = hex }
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if hex.caseInsensitiveCompare(project.color) == .orderedSame {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section {
                    Button("Delete Project", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .disabled(model.isReadOnly)
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Project", role: .destructive) {
                    do {
                        try model.deleteProject(id, undoManager: undoManager)
                        dismiss()
                    } catch {
                        cantDelete = true
                    }
                }
            }
            .alert("“\(project.name)” Has Logged Time", isPresented: $cantDelete) {
                Button("Archive") { setArchived(true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A project with entries can't be deleted. Archive it instead, or merge it on a Mac.")
            }
        } else {
            ContentUnavailableView("Project Deleted", systemImage: "trash")
        }
    }

    private func update(_ actionName: String, _ change: (inout Project) -> Void) {
        model.updateProject(id, actionName: actionName, undoManager: undoManager, change)
    }

    private func setArchived(_ archived: Bool) {
        update(archived ? "Archive Project" : "Unarchive Project") { $0.archived = archived }
    }
}
#endif

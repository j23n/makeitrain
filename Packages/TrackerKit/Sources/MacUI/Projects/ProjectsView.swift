#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A client or project in the outline, with the time logged to it.
struct ProjectListRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case client(UUID)
        case noClient
        case project(UUID)
    }

    var id: Kind
    var title: String
    var color: String?
    var archived: Bool
    var milliseconds: Int64
    var children: [ProjectListRow]?

    /// Projects without a client come first under "No client", then each
    /// client with its projects. Archived ones only when asked for.
    static func rows(ledger: Ledger, resolved: [ResolvedEntry], now: Timestamp, showArchived: Bool) -> [ProjectListRow] {
        var time: [UUID: Int64] = [:]
        for entry in resolved {
            if let projectID = entry.entry.projectID {
                time[projectID, default: 0] += entry.duration(now: now)
            }
        }
        let clients = ledger.liveClients()
        let clientIDs = Set(clients.map(\.id))
        let projects = ledger.projects.values
            .filter { !$0.isDeleted }
            .sorted { a, b in
                let (nameA, nameB) = (a.name.lowercased(), b.name.lowercased())
                return nameA != nameB ? nameA < nameB : a.id.uuidString < b.id.uuidString
            }

        func projectRows(where belongs: (Project) -> Bool) -> [ProjectListRow] {
            projects.filter { belongs($0) && (showArchived || !$0.archived) }.map { project in
                ProjectListRow(
                    id: .project(project.id),
                    title: project.name,
                    color: project.color,
                    archived: project.archived,
                    milliseconds: time[project.id] ?? 0,
                    children: nil
                )
            }
        }
        func totalTime(where belongs: (Project) -> Bool) -> Int64 {
            projects.filter(belongs).reduce(0) { $0 + (time[$1.id] ?? 0) }
        }

        var result: [ProjectListRow] = []
        let noClient: (Project) -> Bool = { project in project.clientID.map { !clientIDs.contains($0) } ?? true }
        let unfiled = projectRows(where: noClient)
        if !unfiled.isEmpty {
            result.append(ProjectListRow(
                id: .noClient,
                title: "No client",
                color: nil,
                archived: false,
                milliseconds: totalTime(where: noClient),
                children: unfiled
            ))
        }
        for client in clients where showArchived || !client.archived {
            let children = projectRows { $0.clientID == client.id }
            result.append(ProjectListRow(
                id: .client(client.id),
                title: client.name,
                color: nil,
                archived: client.archived,
                milliseconds: totalTime { $0.clientID == client.id },
                children: children.isEmpty ? nil : children
            ))
        }
        return result
    }
}

/// Clients and their projects in an outline, with an inspector to edit,
/// archive, merge and delete them.
struct ProjectsView: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: ProjectListRow.Kind?
    @State private var showArchived = false
    @State private var showInspector = true
    /// Clients folded away; the rest show their projects.
    @State private var collapsed: Set<ProjectListRow.Kind> = []

    init(model: AppModel, selection: ProjectListRow.Kind? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let rows = ProjectListRow.rows(ledger: model.ledger, resolved: model.resolved, now: model.now, showArchived: showArchived)
        List(selection: $selection) {
            ForEach(rows) { row in
                if let children = row.children {
                    DisclosureGroup(isExpanded: Binding(
                        get: { !collapsed.contains(row.id) },
                        set: { expanded in
                            if expanded {
                                collapsed.remove(row.id)
                            } else {
                                collapsed.insert(row.id)
                            }
                        }
                    )) {
                        ForEach(children) { child in
                            ProjectListRowView(row: child)
                                .tag(child.id)
                        }
                    } label: {
                        ProjectListRowView(row: row)
                            .tag(row.id)
                    }
                } else {
                    ProjectListRowView(row: row)
                        .tag(row.id)
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Add a client or a project with the buttons in the toolbar.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showArchived) {
                    Label("Show Archived", systemImage: "archivebox")
                }
                .help("Show archived clients and projects")
                Button(action: addClient) {
                    Label("New Client", systemImage: "person.crop.circle.badge.plus")
                }
                .help("Add a client")
                .disabled(model.isReadOnly)
                Button(action: addProject) {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .help("Add a project, for the selected client if there is one")
                .disabled(model.isReadOnly)
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide the inspector")
            }
        }
        .inspector(isPresented: $showInspector) {
            editor
                .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch selection {
        case .client(let id)?:
            if let client = model.ledger.clients[id], !client.isDeleted {
                ClientEditor(model: model, client: client)
                    .id(id)
            } else {
                noSelection
            }
        case .project(let id)?:
            if let project = model.ledger.projects[id], !project.isDeleted {
                ProjectEditor(model: model, project: project)
                    .id(id)
            } else {
                noSelection
            }
        case .noClient?, nil:
            noSelection
        }
    }

    private var noSelection: some View {
        ContentUnavailableView("No Selection", systemImage: "folder", description: Text("Select a client or project to edit it."))
    }

    private func addClient() {
        let id = model.addClient(named: "New Client", undoManager: undoManager)
        selection = .client(id)
        showInspector = true
    }

    private func addProject() {
        var clientID: UUID?
        switch selection {
        case .client(let id)?: clientID = id
        case .project(let id)?: clientID = model.ledger.projects[id]?.clientID
        case .noClient?, nil: clientID = nil
        }
        let id = model.addProject(named: "New Project", client: clientID, color: ProjectColors.next(in: model.ledger), undoManager: undoManager)
        selection = .project(id)
        showInspector = true
    }
}

/// A client or project with its color and the time logged to it.
struct ProjectListRowView: View {
    let row: ProjectListRow

    var body: some View {
        HStack(spacing: 8) {
            if let color = row.color {
                Circle()
                    .fill(Color(hex: color))
                    .frame(width: 9, height: 9)
            }
            Text(row.title)
                .foregroundStyle(row.archived ? .secondary : .primary)
            if row.archived {
                Text("Archived")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.duration(row.milliseconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// A client's name and archived state, merging it into another client, and
/// deleting it.
struct ClientEditor: View {
    let model: AppModel
    let client: Client
    @Environment(\.undoManager) private var undoManager
    @State private var mergeTarget: Client?
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        let others = model.ledger.liveClients().filter { $0.id != client.id }
        Form {
            Section {
                CommitField(title: "Name", value: client.name) { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    model.updateClient(client.id, actionName: "Rename Client", undoManager: undoManager) { $0.name = trimmed }
                }
                Toggle("Archived", isOn: Binding(
                    get: { client.archived },
                    set: { archived in setArchived(archived) }
                ))
            } footer: {
                Text("An archived client and its projects are hidden from pickers and the menu bar, but stay in reports.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Menu("Merge Into…") {
                    ForEach(others) { other in
                        Button(other.name) {
                            mergeTarget = other
                        }
                    }
                }
                .disabled(others.isEmpty)
                Button("Delete Client…", role: .destructive) {
                    confirmingDelete = true
                }
            } footer: {
                Text("Merging moves every project to the other client and deletes this one, such as when two devices each added the same client.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            "Merge “\(client.name)” into “\(mergeTarget?.name ?? "")”?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            presenting: mergeTarget
        ) { target in
            Button("Merge") {
                try? model.mergeClient(client.id, into: target.id, undoManager: undoManager)
            }
        } message: { target in
            Text("Every project of “\(client.name)” moves to “\(target.name)”, and “\(client.name)” is deleted.")
        }
        .confirmationDialog("Delete “\(client.name)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                do {
                    try model.deleteClient(client.id, undoManager: undoManager)
                } catch {
                    cantDelete = true
                }
            }
        } message: {
            Text("Its projects are deleted too.")
        }
        .alert("“\(client.name)” Has Logged Time", isPresented: $cantDelete) {
            Button("Archive") {
                setArchived(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A client whose projects have entries can't be deleted. Archive it to hide it, or merge it into another client.")
        }
    }

    private func setArchived(_ archived: Bool) {
        model.updateClient(client.id, actionName: archived ? "Archive Client" : "Unarchive Client", undoManager: undoManager) {
            $0.archived = archived
        }
    }
}

/// A project's name, client, color and archived state, merging it into
/// another project, and deleting it.
struct ProjectEditor: View {
    let model: AppModel
    let project: Project
    @Environment(\.undoManager) private var undoManager
    @State private var mergeTarget: Project?
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        let entries = model.resolved.filter { $0.entry.projectID == project.id }
        let others = model.ledger.projects.values
            .filter { !$0.isDeleted && $0.id != project.id }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
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
                    Divider()
                    ForEach(model.ledger.liveClients().filter { !$0.archived || $0.id == project.clientID }) { client in
                        Text(client.name).tag(UUID?.some(client.id))
                    }
                }
                LabeledContent("Color") {
                    HStack(spacing: 6) {
                        ForEach(ProjectColors.palette, id: \.self) { hex in
                            Button {
                                update("Change Color") { $0.color = hex }
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        if hex.caseInsensitiveCompare(project.color) == .orderedSame {
                                            Circle().strokeBorder(.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Toggle("Archived", isOn: Binding(
                    get: { project.archived },
                    set: { archived in setArchived(archived) }
                ))
            } footer: {
                Text("Moving a project to another client moves its history too, including in past reports.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Entries", value: "\(entries.count)")
                LabeledContent("Time Logged", value: Format.duration(entries.reduce(0) { $0 + model.duration(of: $1) }))
            }
            Section {
                Menu("Merge Into…") {
                    ForEach(others) { other in
                        Button(model.ledger.projectTitle(other.id)) {
                            mergeTarget = other
                        }
                    }
                }
                .disabled(others.isEmpty)
                Button("Delete Project…", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            "Merge “\(project.name)” into “\(mergeTarget.map { model.ledger.projectTitle($0.id) } ?? "")”?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            presenting: mergeTarget
        ) { target in
            Button("Merge") {
                try? model.mergeProject(project.id, into: target.id, undoManager: undoManager)
            }
        } message: { target in
            Text("Every entry of “\(project.name)” moves to “\(target.name)”, and “\(project.name)” is deleted.")
        }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                do {
                    try model.deleteProject(project.id, undoManager: undoManager)
                } catch {
                    cantDelete = true
                }
            }
        }
        .alert("“\(project.name)” Has Logged Time", isPresented: $cantDelete) {
            Button("Archive") {
                setArchived(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A project with entries can't be deleted. Archive it to hide it, or merge it into another project.")
        }
    }

    private func update(_ actionName: String, _ change: (inout Project) -> Void) {
        model.updateProject(project.id, actionName: actionName, undoManager: undoManager, change)
    }

    private func setArchived(_ archived: Bool) {
        update(archived ? "Archive Project" : "Unarchive Project") { $0.archived = archived }
    }
}
#endif

#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// iCloud, the first day of the week, clients and projects, and importing
/// entries from calendars and CSV files, for the iPhone's Settings tab and
/// the iPad's Settings screen.
struct SettingsForm: View {
    @Bindable var model: AppModel
    /// Whether it links to the clients and projects. On iPad they're in the
    /// sidebar.
    var showsProjects = true
    /// Saves every entry as a CSV file, where there's a way to, as on iPad.
    var exportAll: (() -> Void)? = nil
    @State private var switching = false
    @State private var switchError: String?
    @State private var importing = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep Data in iCloud Drive", isOn: iCloudBinding)
                    .disabled(switching || (!model.isICloudAvailable && model.storage == .local))
            } footer: {
                Text(storageExplanation)
            }

            if showsProjects {
                Section {
                    NavigationLink("Clients & Projects") {
                        MobileProjectsScreen(model: model)
                    }
                }
            }

            // General rather than Reports, since the iPad's timeline and
            // filters and the calendar import use it as well.
            Section("General") {
                Picker("First Day of the Week", selection: $model.firstWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
            }

            Section {
                Button("Import Calendar Events…") {
                    importingEvents = true
                }
                .disabled(model.isReadOnly)
            } footer: {
                // On iPad the projects are in the sidebar, with their
                // settings on their pages.
                Text(showsProjects
                    ? "Adds the events of each project's calendar as its entries. Choose a project's calendar under Clients & Projects."
                    : "Adds the events of each project's calendar as its entries. To choose a project's calendar, open the project in the sidebar and tap Settings.")
            }

            Section {
                Button("Import CSV…") {
                    importing = true
                }
                .disabled(model.isReadOnly)
            } footer: {
                Text("Adds entries from a CSV file, such as one exported from this app or another time tracker.")
            }

            if let exportAll {
                Section {
                    Button("Export All Entries…", action: exportAll)
                        .disabled(!model.resolved.contains { !$0.isRunning })
                } footer: {
                    Text("Saves every entry as a CSV file, with the columns of a report's.")
                }
            }
        }
        .alert("Couldn't Switch Storage", isPresented: Binding(get: { switchError != nil }, set: { if !$0 { switchError = nil } })) {
            Button("OK") { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                importRequest = try model.importRequest(forFileAt: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importRequest) { request in
            MobileImportSheet(model: model, request: request)
        }
        .sheet(isPresented: $importingEvents) {
            MobileCalendarImportSheet(model: model)
        }
        .alert("Couldn't Import the File", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
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

/// Shows what importing a CSV file adds, and adds it.
struct MobileImportSheet: View {
    let model: AppModel
    let request: ImportRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let count = request.plan.entries.count
        NavigationStack {
            Form {
                ImportSummary(plan: request.plan, ledger: model.ledger)
            }
            .navigationTitle(request.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        model.importEntries(request.plan, undoManager: undoManager)
                        dismiss()
                    }
                    .disabled(count == 0 || model.isReadOnly)
                }
            }
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
                Toggle(isOn: $showArchived) {
                    Label("Show Archived", systemImage: "archivebox")
                }
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

/// A client's name and archived state, and deleting it.
struct MobileClientForm: View {
    let model: AppModel
    let id: UUID
    /// What happens once the client is deleted. Unless given, the form goes
    /// back.
    var deleted: (() -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        if let client = model.ledger.clients[id], !client.isDeleted {
            Form {
                Section {
                    LabeledContent("Name") {
                        CommitField(title: "Name", value: client.name) { name in
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            model.updateClient(id, actionName: "Rename Client", undoManager: undoManager) { $0.name = trimmed }
                        }
                        .multilineTextAlignment(.trailing)
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
                        if let deleted {
                            deleted()
                        } else {
                            dismiss()
                        }
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

/// A project's name, client, color and archived state, its tags, GitHub
/// repositories and calendar, and deleting it.
struct MobileProjectForm: View {
    let model: AppModel
    let id: UUID
    /// Whether it lists the project's tags. On iPad they're on the
    /// project's page.
    var showsTags = true
    /// What happens once the project is deleted. Unless given, the form
    /// goes back.
    var deleted: (() -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        if let project = model.ledger.projects[id], !project.isDeleted {
            Form {
                Section {
                    LabeledContent("Name") {
                        CommitField(title: "Name", value: project.name) { name in
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            update("Rename Project") { $0.name = trimmed }
                        }
                        .multilineTextAlignment(.trailing)
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
                    // Each swatch takes its share of the row and the row's
                    // height, so a finger can hit it.
                    HStack(spacing: 0) {
                        ForEach(ProjectColors.palette, id: \.self) { hex in
                            let chosen = hex.caseInsensitiveCompare(project.color) == .orderedSame
                            Button {
                                update("Change Color") { $0.color = hex }
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if chosen {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(ProjectColors.name(of: hex)))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
                if showsTags {
                    MobileProjectTagsSection(model: model, project: project)
                }
                MobileRepositoriesSection(model: model, project: project)
                MobileProjectCalendarSection(model: model, project: project)
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
                        if let deleted {
                            deleted()
                        } else {
                            dismiss()
                        }
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

#if DEBUG
#Preview("Import") {
    let csv = """
    Date,Client,Project,Notes,Hours
    2026-09-24,Acme,Website redesign,Design review,1.5
    2026-09-24,Initech,Consulting,Kickoff,2
    2026-09-25,,Internal,,banana
    """
    let model = PreviewData.model()
    let plan = try! model.importPlan(for: Data(csv.utf8))
    return MobileImportSheet(model: model, request: ImportRequest(fileName: "harvest.csv", plan: plan))
}

#Preview("Clients & Projects") {
    NavigationStack {
        MobileProjectsScreen(model: PreviewData.model())
    }
}

#Preview("Client") {
    NavigationStack {
        MobileClientForm(model: PreviewData.model(), id: PreviewData.acme)
    }
}

#Preview("Project") {
    NavigationStack {
        MobileProjectForm(model: PreviewData.model(), id: PreviewData.website)
    }
}
#endif
#endif

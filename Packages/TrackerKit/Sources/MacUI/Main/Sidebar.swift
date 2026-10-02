#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// What the main window shows: one of its screens, or the page of a client,
/// a project, or the entries without a project.
enum SidebarItem: Hashable {
    case timeline, entries, reports
    case client(UUID)
    case project(UUID)
    case unassigned

    /// The screens above the clients and projects.
    static let screens: [SidebarItem] = [.timeline, .entries, .reports]

    /// How the window remembers it, such as "reports" or "project:" and the
    /// project's id.
    var key: String {
        switch self {
        case .timeline: "timeline"
        case .entries: "entries"
        case .reports: "reports"
        case .client(let id): "client:\(id.uuidString)"
        case .project(let id): "project:\(id.uuidString)"
        case .unassigned: "unassigned"
        }
    }

    /// The item a key stands for, or nil for one that's gone, such as the
    /// screens that projects' pages replaced.
    init?(key: String) {
        switch key {
        case "timeline": self = .timeline
        case "entries": self = .entries
        case "reports": self = .reports
        case "unassigned": self = .unassigned
        default:
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
            switch parts[0] {
            case "client": self = .client(id)
            case "project": self = .project(id)
            default: return nil
            }
        }
    }

    /// A screen's name and symbol; nil for a page.
    var screen: (title: String, icon: String)? {
        switch self {
        case .timeline: (title: "Timeline", icon: "calendar.day.timeline.left")
        case .entries: (title: "Entries", icon: "list.bullet.rectangle")
        case .reports: (title: "Reports", icon: "chart.bar.xaxis")
        case .client, .project, .unassigned: nil
        }
    }
}

/// A client or project to add, for the sheet that asks for its name.
enum NewRecord: Hashable, Identifiable {
    case client
    /// A project, for a client or none.
    case project(UUID?)

    var id: Self { self }
}

/// The main window's sidebar: the timeline, the entries and the reports;
/// then each client with its projects, the projects without a client and
/// the entries without a project, each opening its page; and the archived
/// clients and projects, folded away. A menu at the bottom adds a client or
/// a project.
struct Sidebar: View {
    let model: AppModel
    @Binding var selection: SidebarItem
    /// Asks for a new client's or project's name.
    let add: (NewRecord) -> Void
    @Environment(\.undoManager) private var undoManager
    /// Clients folded away; the rest show their projects.
    @State private var collapsed: Set<UUID> = []
    @State private var showsArchived = false

    var body: some View {
        let tree = ProjectTree(ledger: model.ledger)
        List(selection: Binding<SidebarItem?>(get: { selection }, set: { if let new = $0 { selection = new } })) {
            Section {
                ForEach(SidebarItem.screens, id: \.self) { item in
                    if let screen = item.screen {
                        Label(screen.title, systemImage: screen.icon)
                            .tag(item)
                    }
                }
            }
            Section("Projects") {
                ForEach(tree.clients) { branch in
                    clientRow(branch)
                }
                ForEach(tree.unfiled) { project in
                    projectRow(project, title: project.name)
                }
                if model.resolved.contains(where: { $0.entry.projectID == nil }) {
                    Label {
                        Text("Unassigned")
                    } icon: {
                        ProjectDot(color: nil, size: 10)
                    }
                    .help("The entries without a project, and their tags")
                    .tag(SidebarItem.unassigned)
                }
                if tree.clients.isEmpty, tree.unfiled.isEmpty {
                    Button {
                        add(.project(nil))
                    } label: {
                        Label("New Project…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isReadOnly)
                }
            }
            if !tree.archivedClients.isEmpty || !tree.archivedProjects.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsArchived) {
                        ForEach(tree.archivedClients) { branch in
                            clientRow(branch)
                        }
                        ForEach(tree.archivedProjects) { project in
                            projectRow(project, title: model.ledger.projectTitle(project.id))
                        }
                    } label: {
                        Label("Archived", systemImage: "archivebox")
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Notices(model: model)
                Menu {
                    Button("New Project…") {
                        add(.project(selectedClient))
                    }
                    Button("New Client…") {
                        add(.client)
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .disabled(model.isReadOnly)
                .help("Add a project or a client")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    /// A client, with its projects under it unless it's folded.
    @ViewBuilder
    private func clientRow(_ branch: ProjectTree.Branch) -> some View {
        if branch.projects.isEmpty {
            clientLabel(branch.client)
        } else {
            DisclosureGroup(isExpanded: expansion(of: branch.client.id)) {
                ForEach(branch.projects) { project in
                    projectRow(project, title: project.name)
                }
            } label: {
                clientLabel(branch.client)
            }
        }
    }

    private func clientLabel(_ client: Client) -> some View {
        Label(client.name, systemImage: "briefcase")
            .contextMenu {
                Group {
                    Button("New Project…") {
                        add(.project(client.id))
                    }
                    Button(client.archived ? "Unarchive Client" : "Archive Client") {
                        model.updateClient(client.id, actionName: client.archived ? "Unarchive Client" : "Archive Client", undoManager: undoManager) {
                            $0.archived.toggle()
                        }
                    }
                }
                .disabled(model.isReadOnly)
            }
            .tag(SidebarItem.client(client.id))
    }

    private func projectRow(_ project: Project, title: String) -> some View {
        let running = model.running?.entry.projectID == project.id
        return Label {
            Text(title)
        } icon: {
            ProjectDot(color: Color(hex: project.color), size: 10)
        }
        .contextMenu {
            Group {
                // Starting the running timer's project again would only
                // cut its entry in two.
                Button("Start Timer") {
                    model.startTimer(Combination(projectID: project.id, tags: []), undoManager: undoManager)
                }
                .disabled(running || model.ledger.isArchived(project: project.id))
                Button(project.archived ? "Unarchive Project" : "Archive Project") {
                    model.updateProject(project.id, actionName: project.archived ? "Unarchive Project" : "Archive Project", undoManager: undoManager) {
                        $0.archived.toggle()
                    }
                }
            }
            .disabled(model.isReadOnly)
        }
        .tag(SidebarItem.project(project.id))
    }

    private func expansion(of clientID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(clientID) },
            set: { expanded in
                if expanded {
                    collapsed.remove(clientID)
                } else {
                    collapsed.insert(clientID)
                }
            }
        )
    }

    /// The client a new project goes to: the one shown, or the shown
    /// project's.
    private var selectedClient: UUID? {
        switch selection {
        case .client(let id): id
        case .project(let id): model.ledger.projects[id]?.clientID
        case .timeline, .entries, .reports, .unassigned: nil
        }
    }
}

/// Asks for a new client's or project's name, and a project's client, and
/// adds it.
struct NewRecordSheet: View {
    let model: AppModel
    let record: NewRecord
    /// The main window's, so adding undoes there.
    let undoManager: UndoManager?
    /// Shows what was added.
    let added: (SidebarItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var clientID: UUID?

    init(model: AppModel, record: NewRecord, undoManager: UndoManager?, added: @escaping (SidebarItem) -> Void) {
        self.model = model
        self.record = record
        self.undoManager = undoManager
        self.added = added
        if case .project(let clientID) = record {
            _clientID = State(initialValue: clientID)
        }
    }

    private var isProject: Bool {
        record != .client
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isProject ? "New Project" : "New Client")
                .font(.headline)
            Form {
                TextField("Name:", text: $name, prompt: Text(isProject ? "Website redesign" : "Acme"))
                    .onSubmit(save)
                if isProject {
                    Picker("Client:", selection: $clientID) {
                        Text("No client").tag(UUID?.none)
                        Divider()
                        ForEach(model.ledger.liveClients().filter { !$0.archived || $0.id == clientID }) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isProject {
            let id = model.addProject(named: trimmed, client: clientID, color: ProjectColors.next(in: model.ledger), undoManager: undoManager)
            added(.project(id))
        } else {
            added(.client(model.addClient(named: trimmed, undoManager: undoManager)))
        }
        dismiss()
    }
}

#if DEBUG
#Preview("Sidebar") {
    Sidebar(model: PreviewData.model(), selection: .constant(.project(PreviewData.website)), add: { _ in })
        .listStyle(.sidebar)
        .frame(width: 220, height: 600)
}

#Preview("A Freelancer's Sidebar") {
    Sidebar(model: PreviewData.model(PreviewData.ownerLedger), selection: .constant(.reports), add: { _ in })
        .listStyle(.sidebar)
        .frame(width: 220, height: 500)
}

#Preview("No Projects") {
    Sidebar(model: PreviewData.model(Ledger()), selection: .constant(.timeline), add: { _ in })
        .listStyle(.sidebar)
        .frame(width: 220, height: 400)
}

#Preview("New Project") {
    NewRecordSheet(model: PreviewData.model(), record: .project(PreviewData.acme), undoManager: nil) { _ in }
}
#endif
#endif

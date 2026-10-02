#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Clients and their projects on iPad, with the time logged to each, and
/// the selected one's settings in the inspector: a client's name and
/// archived state, and a project's client, color, tags, GitHub repositories
/// and calendar.
struct PadProjectsScreen: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: ProjectListRow.Kind?
    @State private var showArchived = false
    @State private var adding: Adding?
    @State private var newName = ""
    @AppStorage("projects.inspector") private var showInspector = true

    enum Adding {
        case client, project
    }

    init(model: AppModel, selection: ProjectListRow.Kind? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let rows = ProjectListRow.rows(ledger: model.ledger, resolved: model.resolved, now: model.now, showArchived: showArchived)
        List(selection: $selection) {
            ForEach(rows) { row in
                Section {
                    ProjectListRowView(row: row)
                        .fontWeight(.semibold)
                        .tag(row.id)
                        .selectionDisabled(row.id == .noClient)
                    ForEach(row.children ?? []) { child in
                        ProjectListRowView(row: child)
                            .padding(.leading, 18)
                            .tag(child.id)
                    }
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Add a client or a project with the + button.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showArchived) {
                    Label("Show Archived", systemImage: "archivebox")
                }
                .toggleStyle(.button)
                .help("Show archived clients and projects")
                Menu {
                    Button {
                        startAdding(.client)
                    } label: {
                        Label("New Client", systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        startAdding(.project)
                    } label: {
                        Label("New Project", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add a client, or a project for the selected client")
                .disabled(model.isReadOnly)
                PadInspectorButton(shown: $showInspector)
            }
        }
        .padInspector(shown: $showInspector, hasSelection: hasEditableSelection) {
            selection = nil
        } inspector: {
            NavigationStack {
                editor
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
        .onChange(of: selection) { _, newSelection in
            if newSelection != nil {
                showInspector = true
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch selection {
        case .client(let id)?:
            MobileClientForm(model: model, id: id) {
                selection = nil
            }
            .id(id)
        case .project(let id)?:
            MobileProjectForm(model: model, id: id) {
                selection = nil
            }
            .id(id)
        case .noClient?, nil:
            ContentUnavailableView("No Selection", systemImage: "folder", description: Text("Tap a client or project to edit it."))
        }
    }

    private var hasEditableSelection: Bool {
        switch selection {
        case .client?, .project?: true
        case .noClient?, nil: false
        }
    }

    private func startAdding(_ kind: Adding) {
        newName = ""
        adding = kind
    }

    private func add(_ kind: Adding) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch kind {
        case .client:
            selection = .client(model.addClient(named: name, undoManager: undoManager))
        case .project:
            let id = model.addProject(named: name, client: selectedClient, color: ProjectColors.next(in: model.ledger), undoManager: undoManager)
            selection = .project(id)
        }
    }

    /// The client a new project goes to: the one selected, or the selected
    /// project's.
    private var selectedClient: UUID? {
        switch selection {
        case .client(let id)?: id
        case .project(let id)?: model.ledger.projects[id]?.clientID
        case .noClient?, nil: nil
        }
    }
}

#if DEBUG
#Preview("Project") {
    NavigationStack {
        PadProjectsScreen(model: PreviewData.model(), selection: .project(PreviewData.website))
            .navigationTitle("Clients & Projects")
            .navigationBarTitleDisplayMode(.inline)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadProjectsPreview")!)
}

#Preview("Client") {
    NavigationStack {
        PadProjectsScreen(model: PreviewData.model(), selection: .client(PreviewData.acme))
            .navigationTitle("Clients & Projects")
            .navigationBarTitleDisplayMode(.inline)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadProjectsPreview")!)
}

#Preview("No Projects") {
    NavigationStack {
        PadProjectsScreen(model: PreviewData.model(Ledger()))
            .navigationTitle("Clients & Projects")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
#endif

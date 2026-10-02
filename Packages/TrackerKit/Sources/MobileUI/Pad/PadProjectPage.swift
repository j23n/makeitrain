#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A project's page on iPad, as on the Mac: its time this week, this month
/// and in all, its last twelve weeks, and its tags with their time, the
/// ones that refer to issues grouped by repository, with a button to start
/// its timer. The inspector, or a sheet in a narrow window, has the
/// project's settings, or the tapped tag's, and stays closed until one is
/// asked for.
///
/// The entries without a project have a page like it, with their tags and
/// no settings.
struct PadProjectPage: View {
    let model: AppModel
    /// Nil for the unassigned entries.
    let projectID: UUID?
    /// Shows another screen or page, as after deleting this project.
    let select: (PadItem) -> Void
    /// The selected tag's id.
    @State private var selectedTag: String?
    @State private var showsInspector = false

    init(model: AppModel, projectID: UUID?, selectedTag: String? = nil, select: @escaping (PadItem) -> Void) {
        self.model = model
        self.projectID = projectID
        self.select = select
        _selectedTag = State(initialValue: selectedTag)
        _showsInspector = State(initialValue: selectedTag != nil)
    }

    var body: some View {
        if let projectID, model.ledger.projects[projectID].map(\.isDeleted) ?? true {
            ContentUnavailableView(
                "Project Deleted",
                systemImage: "trash",
                description: Text("It was deleted, or merged into another project.")
            )
        } else {
            page
        }
    }

    private var page: some View {
        let overview = ProjectOverview(
            projects: [projectID],
            ledger: model.ledger,
            resolved: model.resolved,
            today: model.today,
            firstWeekday: model.firstWeekday,
            now: model.now
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(name, subtitle: subtitle, archived: archived) {
                    ProjectBadge(name: name, color: projectID == nil ? nil : model.ledger.color(ofProject: projectID))
                } actions: {
                    ProjectTimerButton(model: model, projectID: projectID)
                }
                if overview.entryCount == 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No Time Yet")
                            .font(.headline)
                        Text("Start a timer for \(name), and its time, its weeks and its tags show up here.")
                            .foregroundStyle(.secondary)
                    }
                    .card()
                } else {
                    ProjectFigures(overview: overview)
                    WeeksChart(overview: overview)
                    ProjectTagList(overview: overview, color: model.ledger.color(ofProject: projectID), selection: $selectedTag)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if projectID != nil {
                    Button(action: toggleSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Show or hide the project's name, client, color, repositories and calendar")
                }
            }
        }
        .padInspector(shown: $showsInspector, hasSelection: showsInspector && (projectID != nil || selectedTag != nil)) {
            showsInspector = false
            selectedTag = nil
        } inspector: {
            NavigationStack {
                inspector(overview)
            }
        }
        .onChange(of: selectedTag) { _, tag in
            if tag != nil {
                showsInspector = true
            }
        }
    }

    private var name: String {
        projectID.flatMap { model.ledger.projects[$0]?.name } ?? "Unassigned"
    }

    private var subtitle: String {
        guard let projectID else { return "Entries without a project" }
        return model.ledger.client(forProject: projectID)?.name ?? "No client"
    }

    private var archived: Bool {
        projectID.map { model.ledger.isArchived(project: $0) } ?? false
    }

    /// The selected tag's settings, or else the project's.
    @ViewBuilder
    private func inspector(_ overview: ProjectOverview) -> some View {
        if let id = selectedTag, let tag = overview.tag(id) {
            TagForm(model: model, projectID: projectID, tag: tag, projectTags: overview.tagNames) { renamed in
                selectedTag = renamed.lowercased()
            }
            .id(tag.id)
        } else if let projectID {
            MobileProjectForm(model: model, id: projectID, showsTags: false) {
                select(.timeline)
            }
            .id(projectID)
        } else {
            ContentUnavailableView("No Tag Selected", systemImage: "tag", description: Text("Tap a tag to rename, merge or remove it."))
        }
    }

    /// Shows the project's settings, or hides them when they're shown.
    private func toggleSettings() {
        if showsInspector, selectedTag == nil {
            showsInspector = false
        } else {
            selectedTag = nil
            showsInspector = true
        }
    }
}

/// A client's page on iPad, as on the Mac: its time this week, this month
/// and in all, its last twelve weeks stacked by project, and its projects
/// with their time, which open their pages. The inspector, or a sheet in a
/// narrow window, has the client's settings.
struct PadClientPage: View {
    let model: AppModel
    let clientID: UUID
    /// Shows another screen or page, such as a project's.
    let select: (PadItem) -> Void
    /// Asks for a new project's name.
    let add: (PadNewRecord) -> Void
    @State private var showsInspector = false

    var body: some View {
        if let client = model.ledger.clients[clientID], !client.isDeleted {
            page(client)
        } else {
            ContentUnavailableView(
                "Client Deleted",
                systemImage: "trash",
                description: Text("It was deleted, or merged into another client.")
            )
        }
    }

    private func page(_ client: Client) -> some View {
        let projects = model.ledger.projects.values
            .filter { $0.clientID == clientID && !$0.isDeleted }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        let overview = ProjectOverview(
            projects: Set(projects.map { Optional($0.id) }),
            ledger: model.ledger,
            resolved: model.resolved,
            today: model.today,
            firstWeekday: model.firstWeekday,
            now: model.now
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(client.name, subtitle: projects.count == 1 ? "1 project" : "\(projects.count) projects", archived: client.archived) {
                    ClientBadge()
                } actions: {
                    Button {
                        add(.project(clientID))
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isReadOnly)
                }
                ProjectFigures(overview: overview)
                WeeksChart(overview: overview)
                ClientProjectList(projects: projects, overview: overview, ledger: model.ledger) { projectID in
                    select(.project(projectID))
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Show or hide the client's name and archiving, and deleting it")
            }
        }
        .padInspector(shown: $showsInspector, hasSelection: showsInspector) {
            showsInspector = false
        } inspector: {
            NavigationStack {
                MobileClientForm(model: model, id: clientID) {
                    select(.timeline)
                }
            }
        }
    }
}

/// Renames a tag on its project's entries, merging it into another of the
/// project's tags when given that tag's name, or removes it from them.
struct TagForm: View {
    let model: AppModel
    /// The tag's project, or nil for the unassigned entries'.
    let projectID: UUID?
    let tag: ProjectOverview.Tag
    /// The project's tags.
    let projectTags: [String]
    let renamed: (String) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var mergeInto: String?
    @State private var confirmingRemove = false

    var body: some View {
        let project = model.ledger.projectTitle(projectID)
        Form {
            Section {
                LabeledContent("Project") {
                    ProjectLabel(ledger: model.ledger, projectID: projectID)
                }
                LabeledContent("Name") {
                    CommitField(title: "Name", value: tag.name) { name in
                        guard let cleaned = Tags.normalize([name]).first, cleaned != tag.name else { return }
                        if let existing = projectTags.first(where: { Tags.same($0, cleaned) && !Tags.same($0, tag.name) }) {
                            mergeInto = existing
                        } else {
                            rename(to: cleaned)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                LabeledContent("Entries", value: "\(tag.count)")
                LabeledContent("Time Logged", value: Format.duration(tag.milliseconds))
            } footer: {
                Text("Renaming a tag changes it on this project's entries only. Renaming it to another of the project's tags merges the two.")
            }
            if let url = tag.url {
                Section {
                    Link(destination: url) {
                        Label("Open \(tag.name) on GitHub", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text(url.absoluteString)
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Remove from the Project's Entries…", role: .destructive) {
                    confirmingRemove = true
                }
            }
        }
        .disabled(model.isReadOnly)
        .navigationTitle(tag.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Merge “\(tag.name)” into “\(mergeInto ?? "")”?",
            isPresented: Binding(get: { mergeInto != nil }, set: { if !$0 { mergeInto = nil } }),
            titleVisibility: .visible,
            presenting: mergeInto
        ) { target in
            Button("Merge") {
                rename(to: target)
            }
        } message: { target in
            Text("Every entry of \(project) tagged “\(tag.name)” is tagged “\(target)” instead.")
        }
        .confirmationDialog("Remove “\(tag.name)” from every entry of \(project)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.removeTag(tag.name, fromProject: projectID, undoManager: undoManager)
            }
        }
    }

    private func rename(to name: String) {
        model.renameTag(tag.name, to: name, inProject: projectID, undoManager: undoManager)
        renamed(name)
    }
}

#if DEBUG
#Preview("A Freelancer's Project") {
    NavigationStack {
        PadProjectPage(model: PreviewData.model(PreviewData.ownerLedger), projectID: PreviewData.quotlify) { _ in }
            .navigationTitle("Quotlify")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Tag Selected") {
    NavigationStack {
        PadProjectPage(model: PreviewData.model(), projectID: PreviewData.mobileApp, selectedTag: "api#57") { _ in }
            .navigationTitle("Mobile app")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Unassigned") {
    NavigationStack {
        PadProjectPage(model: PreviewData.model(), projectID: nil) { _ in }
            .navigationTitle("Unassigned")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Client") {
    NavigationStack {
        PadClientPage(model: PreviewData.model(), clientID: PreviewData.acme, select: { _ in }, add: { _ in })
            .navigationTitle("Acme")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
#endif

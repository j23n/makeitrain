#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A project's page: its time this week, this month and in all, its last
/// twelve weeks, and its tags with their time, the ones that refer to
/// issues grouped by repository, with a button to start its timer. The
/// inspector has the project's settings, or the selected tag's, and stays
/// closed until one is asked for.
///
/// The entries without a project have a page like it, with their tags and
/// no settings.
struct ProjectPage: View {
    let model: AppModel
    /// Nil for the unassigned entries.
    let projectID: UUID?
    /// Shows another page, such as the project this one was merged into.
    let select: (SidebarItem) -> Void
    @Environment(\.undoManager) private var undoManager
    /// The selected tag's id.
    @State private var selectedTag: String?
    @State private var showsInspector = false

    init(model: AppModel, projectID: UUID?, selectedTag: String? = nil, select: @escaping (SidebarItem) -> Void) {
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
                header
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
                    ProjectTagList(overview: overview, color: color, selection: $selectedTag)
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
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Show or hide the project's name, client, color, repositories and calendar")
                }
            }
        }
        .inspector(isPresented: inspectorShown) {
            inspector(overview)
                .inspectorWidth()
        }
        .onChange(of: selectedTag) { _, tag in
            if tag != nil {
                showsInspector = true
            }
        }
        .onExitCommand {
            selectedTag = nil
        }
    }

    // MARK: Header

    /// The project's color and name, its client, and its timer.
    private var header: some View {
        HStack(spacing: 14) {
            ProjectBadge(name: name, color: projectID == nil ? nil : color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.title.weight(.semibold))
                        .lineLimit(1)
                    if archived {
                        Text("Archived")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            timerButton
        }
    }

    /// Starts a timer for the project, or stops it while it runs.
    @ViewBuilder
    private var timerButton: some View {
        if let running = model.running, running.entry.projectID == projectID {
            Button {
                model.stopTimer(undoManager: undoManager)
            } label: {
                Label("Stop Timer", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.isReadOnly)
            .help("Stop the timer")
        } else {
            Button {
                model.startTimer(Combination(projectID: projectID, tags: []), undoManager: undoManager)
            } label: {
                Label("Start Timer", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isReadOnly || archived)
            .help(model.running == nil ? "Start a timer for \(name)" : "Stop the running timer and start one for \(name)")
        }
    }

    private var name: String {
        projectID.flatMap { model.ledger.projects[$0]?.name } ?? "Unassigned"
    }

    private var subtitle: String {
        guard let projectID else { return "Entries without a project" }
        return model.ledger.client(forProject: projectID)?.name ?? "No client"
    }

    private var color: Color {
        model.ledger.color(ofProject: projectID)
    }

    private var archived: Bool {
        projectID.map { model.ledger.isArchived(project: $0) } ?? false
    }

    // MARK: Inspector

    /// Open while asked for, and while there's something in it: the
    /// project's settings, or the unassigned entries' selected tag.
    private var inspectorShown: Binding<Bool> {
        Binding(
            get: { showsInspector && (projectID != nil || selectedTag != nil) },
            set: { showsInspector = $0 }
        )
    }

    /// The selected tag's settings, or else the project's.
    @ViewBuilder
    private func inspector(_ overview: ProjectOverview) -> some View {
        if let id = selectedTag, let tag = overview.tag(id) {
            TagEditor(model: model, projectID: projectID, tag: tag, projectTags: overview.tagNames) { renamed in
                selectedTag = renamed.lowercased()
            }
            .id(tag.id)
        } else if let projectID, let project = model.ledger.projects[projectID], !project.isDeleted {
            ProjectEditor(model: model, project: project) { target in
                select(.project(target))
            }
            .id(projectID)
        } else {
            ContentUnavailableView("No Tag Selected", systemImage: "tag", description: Text("Select a tag to rename, merge or remove it."))
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

#if DEBUG
#Preview("A Freelancer's Project") {
    ProjectPage(model: PreviewData.model(PreviewData.ownerLedger), projectID: PreviewData.quotlify) { _ in }
        .frame(width: 1000, height: 900)
}

#Preview("Tag Selected") {
    ProjectPage(model: PreviewData.model(), projectID: PreviewData.mobileApp, selectedTag: "api#57") { _ in }
        .frame(width: 1200, height: 800)
}

#Preview("Narrow") {
    ProjectPage(model: PreviewData.model(PreviewData.ownerLedger), projectID: PreviewData.flasks) { _ in }
        .frame(width: 680, height: 800)
}

#Preview("Unassigned") {
    ProjectPage(model: PreviewData.model(), projectID: nil) { _ in }
        .frame(width: 1000, height: 640)
}

#Preview("No Time Yet") {
    let model = PreviewData.model(Ledger(projects: [Project(id: PreviewData.website, name: "Website redesign", updated: PreviewData.now)]))
    return ProjectPage(model: model, projectID: PreviewData.website) { _ in }
        .frame(width: 1000, height: 500)
}
#endif
#endif

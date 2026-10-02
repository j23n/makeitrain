#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A client's page: its time this week, this month and in all, its last
/// twelve weeks stacked by project, and its projects with their time and a
/// bar for each, which open their pages. The inspector has the client's
/// settings, and stays closed until they're asked for.
struct ClientPage: View {
    let model: AppModel
    let clientID: UUID
    /// Shows another page, such as a project's.
    let select: (SidebarItem) -> Void
    /// Asks for a new project's name.
    let add: (NewRecord) -> Void
    @State private var showsInspector = false
    @ScaledMetric private var nameWidth: CGFloat = 200
    @ScaledMetric private var figureWidth: CGFloat = 90

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
                header(client, projects: projects.count)
                ProjectFigures(overview: overview)
                WeeksChart(overview: overview)
                projectList(projects, overview: overview)
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
                        .labelStyle(.titleAndIcon)
                }
                .help("Show or hide the client's name and archiving, and merging or deleting it")
            }
        }
        .inspector(isPresented: $showsInspector) {
            ClientEditor(model: model, client: client) { target in
                select(.client(target))
            }
            .id(client.id)
            .inspectorWidth()
        }
    }

    private func header(_ client: Client, projects: Int) -> some View {
        HStack(spacing: 14) {
            ClientBadge()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(client.name)
                        .font(.title.weight(.semibold))
                        .lineLimit(1)
                    if client.archived {
                        Text("Archived")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(projects == 1 ? "1 project" : "\(projects) projects")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Button {
                add(.project(clientID))
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .controlSize(.large)
            .disabled(model.isReadOnly)
            .help("Add a project for \(client.name)")
        }
    }

    /// The client's projects, each with its time in all and a bar for it,
    /// opening its page when clicked.
    private func projectList(_ projects: [Project], overview: ProjectOverview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projects")
                .font(.headline)
                .padding(.bottom, 6)
            if projects.isEmpty {
                Text("No projects yet. Add one with New Project.")
                    .foregroundStyle(.secondary)
            }
            let maximum = projects.map { overview.projects[$0.id] ?? 0 }.max() ?? 0
            ForEach(projects) { project in
                let time = overview.projects[project.id] ?? 0
                Button {
                    select(.project(project.id))
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ProjectDot(color: Color(hex: project.color))
                            Text(project.name)
                                .lineLimit(1)
                            if model.ledger.isArchived(project: project.id) {
                                Text("Archived")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: nameWidth, alignment: .leading)
                        ShareBar(time, of: maximum, color: Color(hex: project.color))
                        Text(Format.duration(time))
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: figureWidth, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(project.name)")
            }
        }
        .card()
    }
}

#if DEBUG
#Preview("Client") {
    ClientPage(model: PreviewData.model(), clientID: PreviewData.acme, select: { _ in }, add: { _ in })
        .frame(width: 1000, height: 760)
}

#Preview("A Freelancer's Client") {
    ClientPage(model: PreviewData.model(PreviewData.ownerLedger), clientID: PreviewData.northbridge, select: { _ in }, add: { _ in })
        .frame(width: 1000, height: 640)
}
#endif
#endif

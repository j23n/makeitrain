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
                    .controlSize(.large)
                    .disabled(model.isReadOnly)
                    .help("Add a project for \(client.name)")
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
}

#if DEBUG
#Preview("Client") {
    ClientPage(model: PreviewData.model(), clientID: PreviewData.acme, select: { _ in }, add: { _ in })
        .frame(width: 1000, height: 760)
}

#Preview("A Freelancer's Client") {
    ClientPage(model: PreviewData.model(PreviewData.ownerLedger), clientID: PreviewData.craftumsoft, select: { _ in }, add: { _ in })
        .frame(width: 1000, height: 640)
}
#endif
#endif

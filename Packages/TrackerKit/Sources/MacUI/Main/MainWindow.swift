#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// The main window: the screens, clients and projects in a sidebar, the
/// screen or page chosen beside it, and the timer in the toolbar.
struct MainWindow: View {
    let model: AppModel
    /// What's shown, as `SidebarItem.key` writes it.
    @SceneStorage private var shown: String
    @Environment(\.undoManager) private var undoManager
    @State private var importing = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false
    @State private var adding: NewRecord?

    init(model: AppModel, item: SidebarItem = .timeline) {
        self.model = model
        _shown = SceneStorage(wrappedValue: item.key, "screen")
    }

    /// What's shown, or the timeline in place of a screen that's gone.
    private var item: SidebarItem {
        SidebarItem(key: shown) ?? .timeline
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model, selection: Binding(get: { item }, set: { shown = $0.key })) { record in
                adding = record
            }
        } detail: {
            detail
                .timerToolbar(title: title, timer: TimerCapsule(model: model).fixedSize())
                // Here rather than beside the import, so the two file dialogs
                // aren't on the same view.
                .exportsEntries(of: model)
        }
        .navigationTitle(title)
        .frame(minWidth: 880, minHeight: 520)
        .focusedSceneValue(\.imports, imports)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                importRequest = try model.importRequest(forFileAt: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importRequest) { request in
            ImportSheet(model: model, request: request, undoManager: undoManager)
        }
        .sheet(isPresented: $importingEvents) {
            CalendarImportSheet(model: model, undoManager: undoManager)
        }
        .sheet(item: $adding) { record in
            NewRecordSheet(model: model, record: record, undoManager: undoManager) { added in
                shown = added.key
            }
        }
        .alert(
            "Couldn't Import the File",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var imports: ImportActions {
        ImportActions {
            importing = true
        } calendar: {
            importingEvents = true
        }
    }

    /// The screen's name, or the client's or project's.
    private var title: String {
        switch item {
        case .timeline, .entries, .reports: item.screen?.title ?? ""
        case .client(let id): model.ledger.clients[id]?.name ?? "Client"
        case .project(let id): model.ledger.projects[id]?.name ?? "Project"
        case .unassigned: "Unassigned"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch item {
        case .timeline:
            TimelineScreen(model: model)
        case .entries:
            EntriesView(model: model, imports: imports)
        case .reports:
            ReportsView(model: model)
        case .client(let id):
            ClientPage(model: model, clientID: id, select: show) { record in
                adding = record
            }
            .id(item)
        case .project(let id):
            ProjectPage(model: model, projectID: id, select: show)
                .id(item)
        case .unassigned:
            ProjectPage(model: model, projectID: nil, select: show)
                .id(item)
        }
    }

    private func show(_ item: SidebarItem) {
        shown = item.key
    }
}

#if DEBUG
#Preview("Timeline") {
    MainWindow(model: PreviewData.model(), item: .timeline)
        .frame(width: 1200, height: 720)
}

#Preview("Entries") {
    MainWindow(model: PreviewData.model(), item: .entries)
        .frame(width: 1200, height: 720)
}

#Preview("Reports") {
    MainWindow(model: PreviewData.model(), item: .reports)
        .frame(width: 1200, height: 800)
}

#Preview("A Freelancer's Reports") {
    MainWindow(model: PreviewData.model(PreviewData.ownerLedger), item: .reports)
        .frame(width: 1200, height: 800)
}

#Preview("A Freelancer's Project") {
    MainWindow(model: PreviewData.model(PreviewData.ownerLedger), item: .project(PreviewData.bookings))
        .frame(width: 1200, height: 900)
}

#Preview("Client") {
    MainWindow(model: PreviewData.model(), item: .client(PreviewData.acme))
        .frame(width: 1200, height: 760)
}

#Preview("Narrow") {
    MainWindow(model: PreviewData.model(PreviewData.ownerLedger), item: .project(PreviewData.bookings))
        .frame(width: 880, height: 720)
}

#Preview("No Data") {
    MainWindow(model: PreviewData.model(Ledger()), item: .entries)
        .frame(width: 1200, height: 720)
}

#Preview("iCloud Unavailable") {
    MainWindow(model: PreviewData.model(state: .iCloudUnavailable), item: .entries)
        .frame(width: 1200, height: 720)
}
#endif
#endif

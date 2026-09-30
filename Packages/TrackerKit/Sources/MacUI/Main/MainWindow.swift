#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// The screens in the main window's sidebar.
enum Screen: String, CaseIterable, Identifiable {
    case timeline, entries, reports, projects, tags

    var id: Self { self }

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .entries: "Entries"
        case .reports: "Reports"
        case .projects: "Clients & Projects"
        case .tags: "Tags"
        }
    }

    var icon: String {
        switch self {
        case .timeline: "calendar.day.timeline.left"
        case .entries: "list.bullet.rectangle"
        case .reports: "chart.bar.xaxis"
        case .projects: "folder"
        case .tags: "tag"
        }
    }
}

/// The main window: the screens in a sidebar, and the timer in the toolbar,
/// between the title and the screen's items.
struct MainWindow: View {
    let model: AppModel
    @SceneStorage private var screen: Screen
    @Environment(\.undoManager) private var undoManager
    @State private var importing = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false

    init(model: AppModel, screen: Screen = .timeline) {
        self.model = model
        _screen = SceneStorage(wrappedValue: screen, "screen")
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Screen?>(get: { screen }, set: { if let new = $0 { screen = new } })) {
                ForEach(Screen.allCases) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                Notices(model: model)
                    .padding(.bottom, 10)
            }
        } detail: {
            detail
                .timerToolbar(ToolbarTimer(model: model))
        }
        .navigationTitle(screen.title)
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

    @ViewBuilder
    private var detail: some View {
        switch screen {
        case .timeline:
            TimelineScreen(model: model)
        case .entries:
            EntriesView(model: model, imports: imports)
        case .reports:
            ReportsView(model: model)
        case .projects:
            ProjectsView(model: model)
        case .tags:
            TagsView(model: model)
        }
    }
}

#if DEBUG
#Preview("Timeline") {
    MainWindow(model: PreviewData.model(), screen: .timeline)
        .frame(width: 1200, height: 720)
}

#Preview("Entries") {
    MainWindow(model: PreviewData.model(), screen: .entries)
        .frame(width: 1200, height: 720)
}

#Preview("Reports") {
    MainWindow(model: PreviewData.model(), screen: .reports)
        .frame(width: 1200, height: 720)
}

#Preview("Clients & Projects") {
    MainWindow(model: PreviewData.model(), screen: .projects)
        .frame(width: 1200, height: 720)
}

#Preview("Tags") {
    MainWindow(model: PreviewData.model(), screen: .tags)
        .frame(width: 1200, height: 720)
}

#Preview("No Data") {
    MainWindow(model: PreviewData.model(Ledger()), screen: .entries)
        .frame(width: 1200, height: 720)
}

#Preview("iCloud Unavailable") {
    MainWindow(model: PreviewData.model(state: .iCloudUnavailable), screen: .entries)
        .frame(width: 1200, height: 720)
}
#endif
#endif

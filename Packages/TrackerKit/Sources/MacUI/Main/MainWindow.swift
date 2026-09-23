#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

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

/// The main window: the screens in a sidebar, and the running timer in the
/// toolbar.
struct MainWindow: View {
    let model: AppModel
    @SceneStorage("screen") private var screen: Screen

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
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TimerControl(model: model)
                    }
                }
        }
        .navigationTitle(screen.title)
        .frame(minWidth: 880, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch screen {
        case .timeline:
            DayTimelineScreen(model: model)
        case .entries:
            EntriesView(model: model)
        case .reports:
            ReportsView(model: model)
        case .projects:
            ProjectsView(model: model)
        case .tags:
            TagsView(model: model)
        }
    }
}

/// The running timer with a button to stop it, or a button to start one.
struct TimerControl: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let running = model.running {
            HStack(spacing: 10) {
                ProjectLabel(ledger: model.ledger, projectID: running.entry.projectID)
                    .frame(maxWidth: 240)
                Text(Format.duration(model.duration(of: running)))
                    .monospacedDigit()
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    Label("Stop Timer", systemImage: "stop.fill")
                }
                .help("Stop the timer")
                .disabled(model.isReadOnly)
            }
        } else {
            Button {
                model.startTimer(undoManager: undoManager)
            } label: {
                Label("Start Timer", systemImage: "play.fill")
            }
            .help("Start a timer without a project")
            .disabled(model.isReadOnly)
        }
    }
}
#endif

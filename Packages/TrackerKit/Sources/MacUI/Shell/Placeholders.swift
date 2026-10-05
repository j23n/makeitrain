#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

// Screens the redesign hasn't reached yet show the earlier ones meanwhile.

struct ProjectsScreen: View {
    let model: AppModel
    let navigator: Navigator

    var body: some View {
        List(model.ledger.pickerProjects()) { project in
            Button {
                navigator.go(.project(project.id))
            } label: {
                ProjectName(ledger: model.ledger, projectID: project.id, showsClient: true)
            }
            .buttonStyle(.plain)
        }
    }
}

struct ProjectScreen: View {
    let model: AppModel
    let navigator: Navigator
    let projectID: UUID

    var body: some View {
        ProjectPage(model: model, projectID: projectID) { item in
            if case let .project(id) = item {
                navigator.go(.project(id))
            }
        }
    }
}
#endif

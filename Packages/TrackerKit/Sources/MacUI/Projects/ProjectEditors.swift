#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

// The settings of a client, a project and a tag, in the inspector of their
// pages.

/// A client's name and archived state, merging it into another client, and
/// deleting it.
struct ClientEditor: View {
    let model: AppModel
    let client: Client
    /// Shows the client this one was merged into.
    let merged: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var mergeTarget: Client?
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        let others = model.ledger.liveClients().filter { $0.id != client.id }
        Form {
            Section {
                CommitField(title: "Name", value: client.name) { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    model.updateClient(client.id, actionName: "Rename Client", undoManager: undoManager) { $0.name = trimmed }
                }
                Toggle("Archived", isOn: Binding(
                    get: { client.archived },
                    set: { archived in setArchived(archived) }
                ))
            } footer: {
                Text("An archived client and its projects are hidden from pickers and the menu bar, but stay in reports.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Menu("Merge Into…") {
                    ForEach(others) { other in
                        Button(other.name) {
                            mergeTarget = other
                        }
                    }
                }
                .disabled(others.isEmpty)
                Button("Delete Client…", role: .destructive) {
                    confirmingDelete = true
                }
            } footer: {
                Text("Merging moves every project to the other client and deletes this one, such as when two devices each added the same client.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            "Merge “\(client.name)” into “\(mergeTarget?.name ?? "")”?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            presenting: mergeTarget
        ) { target in
            Button("Merge") {
                if (try? model.mergeClient(client.id, into: target.id, undoManager: undoManager)) != nil {
                    merged(target.id)
                }
            }
        } message: { target in
            Text("Every project of “\(client.name)” moves to “\(target.name)”, and “\(client.name)” is deleted.")
        }
        .confirmationDialog("Delete “\(client.name)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                do {
                    try model.deleteClient(client.id, undoManager: undoManager)
                } catch {
                    cantDelete = true
                }
            }
        } message: {
            Text("Its projects are deleted too.")
        }
        .alert("“\(client.name)” Has Logged Time", isPresented: $cantDelete) {
            Button("Archive") {
                setArchived(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A client whose projects have entries can't be deleted. Archive it to hide it, or merge it into another client.")
        }
    }

    private func setArchived(_ archived: Bool) {
        model.updateClient(client.id, actionName: archived ? "Archive Client" : "Unarchive Client", undoManager: undoManager) {
            $0.archived = archived
        }
    }
}

/// A project's settings: its name, client, color and archived state, its
/// GitHub repositories and the calendar its events come from, and merging
/// it into another project or deleting it. Its tags and time are on its
/// page.
struct ProjectEditor: View {
    let model: AppModel
    let project: Project
    /// Shows the project this one was merged into.
    let merged: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var mergeTarget: Project?
    @State private var confirmingDelete = false
    @State private var cantDelete = false

    var body: some View {
        let others = model.ledger.projects.values
            .filter { !$0.isDeleted && $0.id != project.id }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
        Form {
            Section {
                CommitField(title: "Name", value: project.name) { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    update("Rename Project") { $0.name = trimmed }
                }
                Picker("Client", selection: Binding(
                    get: { project.clientID },
                    set: { clientID in update("Change Client") { $0.clientID = clientID } }
                )) {
                    Text("No client").tag(UUID?.none)
                    Divider()
                    ForEach(model.ledger.liveClients().filter { !$0.archived || $0.id == project.clientID }) { client in
                        Text(client.name).tag(UUID?.some(client.id))
                    }
                }
                LabeledContent("Color") {
                    HStack(spacing: 6) {
                        ForEach(ProjectColors.palette, id: \.self) { hex in
                            let chosen = hex.caseInsensitiveCompare(project.color) == .orderedSame
                            Button {
                                update("Change Color") { $0.color = hex }
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        if chosen {
                                            Circle().strokeBorder(.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(ProjectColors.name(of: hex))
                            .accessibilityLabel(Text(ProjectColors.name(of: hex)))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
                Toggle("Archived", isOn: Binding(
                    get: { project.archived },
                    set: { archived in setArchived(archived) }
                ))
            } footer: {
                Text("Moving a project to another client moves its history too, including in past reports.")
                    .foregroundStyle(.secondary)
            }
            RepositoriesSection(model: model, project: project)
            ProjectCalendarSection(model: model, project: project)
            Section {
                ProjectChooserButton(ledger: model.ledger, title: "Merge Into…", offersNoProject: false, excluding: project.id) { projectID in
                    mergeTarget = projectID.flatMap { model.ledger.projects[$0] }
                }
                .disabled(others.isEmpty)
                Button("Delete Project…", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            "Merge “\(project.name)” into “\(mergeTarget.map { model.ledger.projectTitle($0.id) } ?? "")”?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            presenting: mergeTarget
        ) { target in
            Button("Merge") {
                if (try? model.mergeProject(project.id, into: target.id, undoManager: undoManager)) != nil {
                    merged(target.id)
                }
            }
        } message: { target in
            Text("Every entry of “\(project.name)” moves to “\(target.name)”, and “\(project.name)” is deleted.")
        }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                do {
                    try model.deleteProject(project.id, undoManager: undoManager)
                } catch {
                    cantDelete = true
                }
            }
        }
        .alert("“\(project.name)” Has Logged Time", isPresented: $cantDelete) {
            Button("Archive") {
                setArchived(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A project with entries can't be deleted. Archive it to hide it, or merge it into another project.")
        }
    }

    private func update(_ actionName: String, _ change: (inout Project) -> Void) {
        model.updateProject(project.id, actionName: actionName, undoManager: undoManager, change)
    }

    private func setArchived(_ archived: Bool) {
        update(archived ? "Archive Project" : "Unarchive Project") { $0.archived = archived }
    }
}

/// Renames a tag on its project's entries, merging it into another of the
/// project's tags when given that tag's name, or removes it from them.
struct TagEditor: View {
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
                CommitField(title: "Name", value: tag.name) { name in
                    guard let cleaned = Tags.normalize([name]).first, cleaned != tag.name else { return }
                    if let existing = projectTags.first(where: { Tags.same($0, cleaned) && !Tags.same($0, tag.name) }) {
                        mergeInto = existing
                    } else {
                        rename(to: cleaned)
                    }
                }
                LabeledContent("Entries", value: "\(tag.count)")
                LabeledContent("Time Logged", value: Format.duration(tag.milliseconds))
            } footer: {
                Text("Renaming a tag changes it on this project's entries only. Renaming it to another of the project's tags merges the two.")
                    .foregroundStyle(.secondary)
            }
            if let url = tag.url {
                Section {
                    Button("Open \(tag.name) on GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                } footer: {
                    Text(url.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Remove from the Project's Entries…", role: .destructive) {
                    confirmingRemove = true
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            "Merge “\(tag.name)” into “\(mergeInto ?? "")”?",
            isPresented: Binding(get: { mergeInto != nil }, set: { if !$0 { mergeInto = nil } }),
            presenting: mergeInto
        ) { target in
            Button("Merge") {
                rename(to: target)
            }
        } message: { target in
            Text("Every entry of \(project) tagged “\(tag.name)” is tagged “\(target)” instead.")
        }
        .confirmationDialog("Remove “\(tag.name)” from every entry of \(project)?", isPresented: $confirmingRemove) {
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
#Preview("Project") {
    let model = PreviewData.model()
    return ProjectEditor(model: model, project: model.ledger.projects[PreviewData.mobileApp]!) { _ in }
        .frame(width: 320, height: 760)
}

#Preview("Client") {
    let model = PreviewData.model()
    return ClientEditor(model: model, client: model.ledger.clients[PreviewData.acme]!) { _ in }
        .frame(width: 320, height: 420)
}

#Preview("Linked Tag") {
    let model = PreviewData.model()
    let overview = PreviewData.overview(of: [PreviewData.website], in: model.ledger)
    return TagEditor(model: model, projectID: PreviewData.website, tag: overview.tag("#42")!, projectTags: overview.tagNames) { _ in }
        .frame(width: 320, height: 420)
}
#endif
#endif

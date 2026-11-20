import SwiftUI
import TrackerCore
import TrackerKit

/// A project's page: its time this week, this month and in all, its last
/// twelve weeks day by day, its tags with the issues they refer to by
/// repository, and its settings beside them. Single keys start its timer,
/// and rename, color, archive or merge it, as on the projects table.
struct ProjectScreen: View {
    let model: AppModel
    let navigator: Navigator
    let projectID: UUID
    @State private var overview: ProjectOverview?
    @State private var selectedTag: String?
    @State private var newName = ""
    @State private var showsAllIssues: Set<String> = []
    @State private var removing: ProjectOverview.Tag?
    @FocusState private var renaming: Bool
    @FocusState private var focused: Bool
    @Environment(\.undoManager) private var undoManager

    private var project: Project? {
        model.ledger.projects[projectID].flatMap { $0.isDeleted ? nil : $0 }
    }

    var body: some View {
        if let project {
            VStack(spacing: 0) {
                breadcrumb(project)
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(project)
                            if let overview {
                                figures(overview)
                                ProjectWeeks(model: model, projectID: projectID, tint: ProjectTint(hex: project.color)) {
                                    navigator.go(.month(model.today))
                                }
                                tags(overview, project: project)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 20)
                    }
                    ProjectSettingsPanel(model: model, project: project) { merged in
                        navigator.go(merged.map { .project($0) } ?? .projects)
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(characters: CharacterSet(charactersIn: "sSrRcCaAmM")) { press in
                guard !isEditingText() else { return .ignored }
                return handleKey(press.characters.lowercased(), project: project)
            }
            .takesUnusedKeys(letters: "srcam")
            .onAppear {
                load()
                focused = true
            }
            .onChange(of: model.revision) { load() }
            .onChange(of: model.now) {
                if overview?.isRunning == true {
                    load()
                }
            }
            .confirmationDialog(
                "Remove “\(removing?.name ?? "")” from all \(project.name) entries?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                presenting: removing
            ) { tag in
                Button("Remove", role: .destructive) {
                    model.removeTag(tag.name, fromProject: projectID, undoManager: undoManager)
                    selectedTag = nil
                }
            }
        } else {
            Text("This project was deleted.")
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() {
        overview = ProjectOverview(project: projectID, model: model)
    }

    /// Whether S starts a timer for the project, or switches to it.
    private func canStart(_ project: Project) -> Bool {
        !project.archived && model.running?.entry.projectID != projectID
    }

    /// What a single key does: S starts the project's timer, and R, C, A
    /// and M rename, color, archive or merge it, putting the line for it in
    /// the command line, as the projects table does. A key that can't act
    /// now, as while the data is read-only, is ignored, so it sounds.
    private func handleKey(_ key: String, project: Project) -> KeyPress.Result {
        guard !model.isReadOnly else { return .ignored }
        let name = project.name.lowercased()
        switch key {
        case "s":
            guard canStart(project) else { return .ignored }
            model.startTimer(EntryDraft(projectID: projectID), undoManager: undoManager)
        case "r":
            model.request = .command("rename \(name) to ")
        case "c":
            model.request = .command("color \(name) ")
        case "a":
            model.updateProject(projectID, actionName: project.archived ? "Unarchive Project" : "Archive Project", undoManager: undoManager) {
                $0.archived.toggle()
            }
        case "m":
            model.request = .command("merge \(name) into ")
        default:
            return .ignored
        }
        return .handled
    }

    private func breadcrumb(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Button {
                navigator.go(.projects)
            } label: {
                Label("Projects", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.link)
            if let client = model.ledger.client(forProject: projectID) {
                Text(client.name).foregroundStyle(Theme.text2)
                Text("›").foregroundStyle(Theme.text3)
            }
            Text(project.name).fontWeight(.semibold)
            Spacer()
            HStack(spacing: 18) {
                if canStart(project) {
                    KeyHint("S", model.running == nil ? "start" : "switch")
                }
                KeyHint("R", "rename")
                KeyHint("C", "color")
                KeyHint("A", project.archived ? "unarchive" : "archive")
                KeyHint("M", "merge")
                KeyHint("⌘[", "back")
            }
            .lineLimit(1)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 24)
        .frame(height: 38)
        .background(Theme.sunken)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func header(_ project: Project) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(ProjectTint(hex: project.color).ink)
                .frame(width: 18, height: 18)
            Text(project.name)
                .font(.system(size: 24, weight: .semibold))
            if let client = model.ledger.client(forProject: projectID) {
                Text(client.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill))
            }
            Spacer()
            if let running = model.running, running.entry.projectID == projectID {
                HStack(spacing: 8) {
                    Circle().fill(Theme.now).frame(width: 7, height: 7)
                    Text("Running ") + Text(Format.duration(model.duration(of: running))).fontWeight(.semibold)
                        + Text(running.entry.note.isEmpty ? "" : " on \(running.entry.note)")
                }
                .font(.system(size: 13))
                .monospacedDigit()
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    HStack(spacing: 6) {
                        Text("Stop")
                        KeyCap("⌘.")
                    }
                }
                .buttonStyle(ChoiceButtonStyle(compact: true))
                .disabled(model.isReadOnly)
            } else if !project.archived {
                Button("Start") {
                    model.startTimer(EntryDraft(projectID: projectID), undoManager: undoManager)
                }
                .buttonStyle(ChoiceButtonStyle(compact: true))
                .disabled(model.isReadOnly)
                .help(model.running == nil ? "Start a timer for \(project.name)" : "Switch the timer to \(project.name)")
            }
        }
    }

    private func figures(_ overview: ProjectOverview) -> some View {
        let running = model.running.flatMap { $0.entry.projectID == projectID ? $0 : nil }
        let longCorrection = longTimer(overview)
        return HStack(spacing: 1) {
            FigureTile("This week", Format.duration(overview.thisWeek), running.map { "\(Format.duration(model.duration(of: $0))) running" } ?? " ")
            FigureTile("This month", Format.duration(overview.thisMonth)) {
                if let longCorrection {
                    HStack(spacing: 4) {
                        Text(longCorrection.text)
                        Button("Fix") {
                            navigator.go(.week(longCorrection.day))
                        }
                        .linkButton()
                    }
                    .foregroundStyle(Theme.amberText)
                    .lineLimit(nil)
                } else {
                    Text(" ")
                }
            }
            FigureTile(
                "All time",
                Format.duration(overview.total),
                overview.firstDay.map { "since \(Format.longDay($0)) · \(overview.entryCount) \(overview.entryCount == 1 ? "entry" : "entries")" } ?? " "
            )
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    /// A timer this month that ran long, as "Includes a 19:25 overnight
    /// timer on Thursday".
    private func longTimer(_ overview: ProjectOverview) -> (text: String, day: LocalDate)? {
        guard let timer = overview.longTimer else { return nil }
        return ("Includes a \(Format.duration(timer.length)) \(timer.overnight ? "overnight " : "")timer on \(Format.weekday(timer.day)) ·", timer.day)
    }

    // MARK: Tags

    private func tags(_ overview: ProjectOverview, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tags").font(.system(size: 14, weight: .semibold))
                    + Text(" · all time").foregroundColor(Theme.text3)
                Spacer()
                Text("Select a tag to edit it")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            if overview.repositories.isEmpty && overview.tags.isEmpty {
                Text("No tags yet. Type them with #, as in #design.")
                    .foregroundStyle(Theme.text3)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(overview.repositories) { repository in
                    tagGroup(
                        title: repository.title,
                        detail: "\(repository.issues.count) \(repository.issues.count == 1 ? "issue" : "issues")",
                        tags: repository.issues,
                        key: repository.id,
                        project: project
                    )
                }
                if !overview.tags.isEmpty {
                    tagGroup(title: "Other tags", detail: "\(overview.tags.count)", tags: overview.tags, key: "other", project: project)
                }
            }
        }
    }

    private func tagGroup(title: String, detail: String, tags: [ProjectOverview.Tag], key: String, project: Project) -> some View {
        let highest = tags.map(\.milliseconds).max() ?? 1
        let shown = showsAllIssues.contains(key) ? tags : Array(tags.prefix(6))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(detail).foregroundStyle(Theme.text3)
            }
            .font(.system(size: 12.5))
            ForEach(shown) { tag in
                if selectedTag == tag.id {
                    renameRow(tag)
                } else {
                    HStack(spacing: 10) {
                        if let url = tag.url {
                            Link(destination: url) {
                                Text(tag.number.map { "#\($0)" } ?? tag.name)
                                    .foregroundStyle(Theme.tag)
                            }
                            .frame(width: 70, alignment: .leading)
                        } else {
                            Text(tag.name)
                                .lineLimit(1)
                                .frame(width: 110, alignment: .leading)
                        }
                        ShareBar(tag.milliseconds, of: highest, color: ProjectTint(hex: project.color).bar, height: 5)
                        Text(Format.duration(tag.milliseconds))
                            .monospacedDigit()
                            .frame(width: 74, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTag = tag.id
                        newName = tag.name
                        renaming = true
                    }
                }
            }
            if tags.count > 6 {
                Button(showsAllIssues.contains(key) ? "Fewer" : "\(tags.count - 6) more") {
                    if showsAllIssues.contains(key) {
                        showsAllIssues.remove(key)
                    } else {
                        showsAllIssues.insert(key)
                    }
                }
                .linkButton()
                .font(.system(size: 12))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    /// The selected tag with a field for its new name, which merges it into
    /// another of the project's tags when it's that tag's name.
    private func renameRow(_ tag: ProjectOverview.Tag) -> some View {
        let others = (overview?.tagNames ?? []).filter { !Tags.same($0, tag.name) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("New name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($renaming)
                    .onSubmit { rename(tag, to: newName) }
                    .onEscape { selectedTag = nil }
                Text(Format.duration(tag.milliseconds))
                    .monospacedDigit()
                Menu {
                    ForEach(others, id: \.self) { other in
                        Button(other) {
                            rename(tag, to: other)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.merge")
                }
                .plainMenu()
                .fixedSize()
                .disabled(others.isEmpty)
                .help("Merge into another tag")
                Button {
                    removing = tag
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Remove from all entries")
            }
            Text("Renames it on \(tag.count) \(tag.count == 1 ? "entry" : "entries"). Another tag's name merges the two.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentFill))
        .disabled(model.isReadOnly)
    }

    /// Renames the tag, or merges it into the project's tag of the new name.
    private func rename(_ tag: ProjectOverview.Tag, to name: String) {
        model.renameTag(tag.name, to: name, inProject: projectID, undoManager: undoManager)
        selectedTag = nil
    }
}

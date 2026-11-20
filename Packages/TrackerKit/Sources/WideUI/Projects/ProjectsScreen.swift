import SwiftUI
import TrackerCore
import TrackerKit

/// Clients and their projects as a table: each project's repositories,
/// calendar on this device, contract, and time this week, this month, over the last
/// twelve weeks and in all. Arrows move, Return opens a project's page, and
/// single keys rename, color, archive, merge or add. A window narrower than
/// the table's columns scrolls it sideways.
struct ProjectsScreen: View {
    let model: AppModel
    let navigator: Navigator
    @State private var filter = ""
    @State private var showsArchived = false
    @State private var selection: UUID?
    @FocusState private var focused: Bool
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let tree = ProjectTree(ledger: model.ledger)
        let stats = model.projectStats
        VStack(alignment: .leading, spacing: 14) {
            header(tree)
            // The table fills the window's width, and a window too narrow
            // for its columns scrolls it sideways, so it never pushes the
            // header and the keys past the window's edges.
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        columnHeaders
                        ForEach(tree.clients) { branch in
                            let projects = visible(branch.projects)
                            if !projects.isEmpty || ProjectSearch.matches(filter, project: "", client: branch.client.name) {
                                clientRow(branch.client, projects: branch.projects, stats: stats)
                                ForEach(projects) { project in
                                    projectRow(project, stats: stats)
                                }
                            }
                        }
                        let unfiled = visible(tree.unfiled)
                        if !unfiled.isEmpty {
                            sectionRow("No client")
                            ForEach(unfiled) { project in
                                projectRow(project, stats: stats)
                            }
                        }
                        unassignedRow(stats)
                        archivedSection(tree, stats: stats)
                    }
                    .frame(width: ProjectColumn.layoutWidth(in: geometry.size.width))
                    // A list shorter than the panel starts at its top, where
                    // a scroll view that scrolls both ways may center it.
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
            HStack(spacing: 18) {
                KeyHint("↑ ↓", "move")
                KeyHint("⏎", "open")
                KeyHint("R", "rename")
                KeyHint("C", "color")
                KeyHint("A", "archive")
                KeyHint("M", "merge")
                KeyHint("N", "new project")
            }
        }
        // As the week's, month's and year's, so the header stays put
        // moving between them.
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard !isEditingText() else { return .ignored }
            moveSelection(by: press.key == .upArrow ? -1 : 1, tree: tree)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isEditingText() else { return .ignored }
            if let selection { navigator.go(.project(selection)) }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "rRcCaAmMnN")) { press in
            guard !isEditingText() else { return .ignored }
            handleKey(press.characters.lowercased())
            return .handled
        }
        .takesUnusedKeys([.upArrow, .downArrow, .return], letters: "rcamn")
        .onAppear {
            focused = true
            // As a project's page does, so a calendar added or renamed
            // since shows.
            model.refreshCalendars()
        }
    }

    // MARK: Header

    private func header(_ tree: ProjectTree) -> some View {
        let clients = tree.clients.count
        let projects = tree.clients.reduce(0) { $0 + $1.projects.count } + tree.unfiled.count
        let archived = tree.archivedClients.count + tree.archivedProjects.count
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Clients and projects")
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text("\(clients) \(clients == 1 ? "client" : "clients") · \(projects) \(projects == 1 ? "project" : "projects")\(archived > 0 ? " · \(archived) archived" : "")")
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.text3)
                TextField("Filter", text: $filter)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .frame(minWidth: 120, idealWidth: 200, maxWidth: 200, minHeight: 28, maxHeight: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.strongLine))
            Toggle("Show archived", isOn: $showsArchived)
                .checkbox()
                .font(.system(size: 12.5))
                .fixedSize()
            Menu {
                Button("New Project…") { model.request = .command("new project ") }
                Button("New Client…") { model.request = .command("new client ") }
            } label: {
                Label("New", systemImage: "plus")
            }
            .plainMenu()
            .fixedSize()
            .disabled(model.isReadOnly)
        }
    }

    private var columnHeaders: some View {
        ProjectTableRow(height: 36) {
            Text("Name")
        } repositories: {
            Text("Repositories")
        } calendar: {
            Text("Calendar on this \(deviceName)")
        } contract: {
            Text("Contract")
        } week: {
            Text("This week")
        } month: {
            Text("This month")
        } spark: {
            Text("Last 12 weeks")
        } total: {
            Text("All time")
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Theme.text3)
    }

    // MARK: Rows

    private func clientRow(_ client: Client, projects: [Project], stats: ProjectStats) -> some View {
        let row = stats.sum(projects.map(\.id))
        return ProjectTableRow(height: 42) {
            HStack(spacing: 8) {
                Text(client.name).fontWeight(.semibold)
                Text("\(projects.count) \(projects.count == 1 ? "project" : "projects")")
                    .foregroundStyle(Theme.text3)
                Spacer(minLength: 4)
                Menu {
                    Button("New Project…") { model.request = .command("new project  for \(client.name.lowercased())") }
                    Button("Rename…") { model.request = .command("rename \(client.name.lowercased()) to ") }
                    Button(client.archived ? "Unarchive" : "Archive") {
                        model.updateClient(client.id, actionName: client.archived ? "Unarchive Client" : "Archive Client", undoManager: undoManager) { $0.archived.toggle() }
                    }
                    Button("Merge Into…") { model.request = .command("merge \(client.name.lowercased()) into ") }
                } label: {
                    Text("⋯").foregroundStyle(Theme.text2)
                }
                .plainMenu()
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Actions for \(client.name)"))
            }
        } repositories: {
            EmptyView()
        } calendar: {
            EmptyView()
        } contract: {
            EmptyView()
        } week: {
            time(row.thisWeek, dim: true)
        } month: {
            time(row.thisMonth, dim: true)
        } spark: {
            EmptyView()
        } total: {
            time(row.total, dim: true)
        }
        .background(Theme.sunken)
    }

    private func sectionRow(_ title: String) -> some View {
        ProjectTableRow(height: 42) {
            Text(title).fontWeight(.semibold).foregroundStyle(Theme.text2)
        } repositories: { EmptyView() } calendar: { EmptyView() } contract: { EmptyView() } week: { EmptyView() } month: { EmptyView() } spark: { EmptyView() } total: { EmptyView() }
        .background(Theme.sunken)
    }

    private func projectRow(_ project: Project, stats: ProjectStats) -> some View {
        let row = stats[project.id]
        let selected = selection == project.id
        let running = model.running?.entry.projectID == project.id
        let calendar = model.linkedCalendar(ofProject: project.id)
        return ProjectTableRow(height: 56) {
            HStack(spacing: 10) {
                colorMenu(project)
                Text(project.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if running {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.now).frame(width: 6, height: 6)
                        Text("running")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                }
            }
            .padding(.leading, 22)
        } repositories: {
            let repositories = project.repositories.compactMap { GitHub.Repository($0) }
            if repositories.isEmpty {
                Button("Add…") { navigator.go(.project(project.id)) }
                    .linkButton()
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(repositories.prefix(2).enumerated()), id: \.offset) { index, repository in
                        HStack(spacing: 4) {
                            if index == 0 {
                                Text("#").fontWeight(.semibold).foregroundStyle(Theme.tag)
                            }
                            Text(repository.name)
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill))
                    }
                }
                .lineLimit(1)
            }
        } calendar: {
            if let calendar {
                Label("\(calendar.title) · \(calendar.account)", systemImage: "calendar")
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            } else {
                Menu("Link a calendar…") {
                    ForEach(model.calendars) { info in
                        Button("\(info.title) · \(info.account)") {
                            model.setCalendar(info.id, forProject: project.id)
                        }
                    }
                }
                .plainMenu()
                .fixedSize()
                .disabled(model.calendars.isEmpty)
            }
        } contract: {
            contractCell(project)
        } week: {
            time(row.thisWeek)
        } month: {
            time(row.thisMonth)
        } spark: {
            Sparkline(values: row.weeks, tint: ProjectTint(hex: project.color))
        } total: {
            time(row.total)
        }
        .background(selected ? Theme.accentFill : Color.clear)
        .overlay {
            if selected {
                Rectangle().strokeBorder(Theme.accentLine)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            navigator.go(.project(project.id))
        }
        .onTapGesture {
            selection = project.id
            focused = true
        }
        .contextMenu {
            Button("Open Project") { navigator.go(.project(project.id)) }
            Button("Rename…") { model.request = .command("rename \(project.name.lowercased()) to ") }
            Button("Archive") {
                model.updateProject(project.id, actionName: "Archive Project", undoManager: undoManager) { $0.archived = true }
            }
            Button("Merge Into…") { model.request = .command("merge \(project.name.lowercased()) into ") }
        }
    }

    /// The project's contract: the time left over a bar, with its hours
    /// and when it ends, or a link to add one on the project's page.
    @ViewBuilder
    private func contractCell(_ project: Project) -> some View {
        if let status = model.contractStatus(ofProject: project.id) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    ContractLeftText(status)
                    Spacer(minLength: 6)
                    Text(status.hasStarted
                        ? "of \(Format.hours(status.contract.hours)) · to \(Format.monthDay(status.contract.end))"
                        : "\(Format.hours(status.contract.hours)) from \(Format.monthDay(status.contract.start))")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                ContractBar(status: status, tint: model.ledger.tint(ofProject: project.id))
            }
        } else if !project.archived {
            Button("Add a contract…") { navigator.go(.project(project.id)) }
                .linkButton()
        }
    }

    private func colorMenu(_ project: Project) -> some View {
        Menu {
            ForEach(Palette.colors, id: \.self) { hex in
                Button(Palette.name(of: hex)) {
                    model.updateProject(project.id, actionName: "Change Color", undoManager: undoManager) { $0.color = hex }
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(ProjectTint(hex: project.color).ink)
                .frame(width: 14, height: 14)
        }
        .plainMenu()
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("\(project.name)'s color, \(Palette.name(of: project.color))"))
    }

    /// The entries without a project: their count, the latest with a link
    /// to assign it in its week, and their times.
    @ViewBuilder
    private func unassignedRow(_ stats: ProjectStats) -> some View {
        let row = stats[nil]
        if row.entryCount > 0 {
            ProjectTableRow(height: 48) {
                HStack(spacing: 10) {
                    Circle().strokeBorder(Theme.text3, lineWidth: 1.5).frame(width: 12, height: 12)
                    Text("Unassigned").fontWeight(.semibold)
                    Text("\(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries")")
                        .foregroundStyle(Theme.text3)
                }
                .lineLimit(1)
            } repositories: {
                if let latest = row.latest {
                    Text(latest.entry.note.isEmpty ? Format.longDay(latest.entry.day) : "\(latest.entry.note), \(Format.weekday(latest.entry.day))")
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
            } calendar: {
                if let latest = row.latest {
                    Button("Assign in Week ›") {
                        navigator.go(.week(latest.entry.day))
                    }
                    .linkButton()
                }
            } contract: {
                EmptyView()
            } week: {
                time(row.thisWeek)
            } month: {
                time(row.thisMonth)
            } spark: {
                EmptyView()
            } total: {
                time(row.total)
            }
        }
    }

    @ViewBuilder
    private func archivedSection(_ tree: ProjectTree, stats: ProjectStats) -> some View {
        let archived = tree.allArchivedProjects
        if !archived.isEmpty {
            VStack(spacing: 0) {
                Button {
                    showsArchived.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showsArchived ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Archived").fontWeight(.semibold)
                        Text(archived.prefix(4).map { "\($0.name) · \(Format.duration(stats[$0.id].total)) total" }.joined(separator: ", "))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                if showsArchived {
                    ForEach(archived) { project in
                        projectRow(project, stats: stats)
                            .opacity(0.7)
                            .contextMenu {
                                Button("Unarchive") {
                                    model.updateProject(project.id, actionName: "Unarchive Project", undoManager: undoManager) { $0.archived = false }
                                }
                            }
                    }
                }
            }
        }
    }

    private func time(_ milliseconds: Int64, dim: Bool = false) -> some View {
        Text(milliseconds > 0 ? Format.duration(milliseconds) : "—")
            .monospacedDigit()
            .foregroundStyle(milliseconds > 0 ? (dim ? Theme.text2 : Theme.text) : Theme.text3)
    }

    // MARK: Filtering and keys

    private func visible(_ projects: [Project]) -> [Project] {
        guard !filter.isEmpty else { return projects }
        return projects.filter { project in
            ProjectSearch.matches(filter, project: project.name, client: model.ledger.client(forProject: project.id)?.name ?? "")
        }
    }

    private func moveSelection(by step: Int, tree: ProjectTree) {
        let order = tree.clients.flatMap { visible($0.projects) } + visible(tree.unfiled)
        guard !order.isEmpty else { return }
        let index = order.firstIndex { $0.id == selection } ?? (step > 0 ? -1 : order.count)
        selection = order[min(max(index + step, 0), order.count - 1)].id
    }

    private func handleKey(_ key: String) {
        guard let id = selection, let project = model.ledger.projects[id] else {
            if key == "n" { model.request = .command("new project ") }
            return
        }
        let name = project.name.lowercased()
        switch key {
        case "r":
            model.request = .command("rename \(name) to ")
        case "c":
            model.request = .command("color \(name) ")
        case "a":
            model.updateProject(id, actionName: "Archive Project", undoManager: undoManager) { $0.archived = true }
        case "m":
            model.request = .command("merge \(name) into ")
        case "n":
            let client = model.ledger.client(forProject: id).map { " for \($0.name.lowercased())" } ?? ""
            model.request = .command("new project " + client)
        default:
            break
        }
    }
}

/// A row of the projects table, with each column's width (`ProjectColumn`).
struct ProjectTableRow<Name: View, Repos: View, Cal: View, Contract: View, Week: View, Month: View, Spark: View, Total: View>: View {
    let height: CGFloat
    @ViewBuilder var name: Name
    @ViewBuilder var repositories: Repos
    @ViewBuilder var calendar: Cal
    @ViewBuilder var contract: Contract
    @ViewBuilder var week: Week
    @ViewBuilder var month: Month
    @ViewBuilder var spark: Spark
    @ViewBuilder var total: Total

    var body: some View {
        HStack(spacing: ProjectColumn.spacing) {
            column(.name, name, alignment: .leading)
            column(.repositories, repositories, alignment: .leading)
            column(.calendar, calendar, alignment: .leading)
            column(.contract, contract, alignment: .leading)
            column(.week, week, alignment: .trailing)
            column(.month, month, alignment: .trailing)
            column(.spark, spark, alignment: .leading)
            column(.total, total, alignment: .trailing)
        }
        .font(.system(size: 13))
        .padding(.horizontal, ProjectColumn.padding)
        .frame(height: height)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    /// A column's cell at its width.
    @ViewBuilder
    private func column(_ column: ProjectColumn, _ content: some View, alignment: Alignment) -> some View {
        if column.isFlexible {
            cell(content, alignment: alignment).frame(minWidth: column.minimumWidth, maxWidth: .infinity)
        } else {
            cell(content, alignment: alignment).frame(width: column.minimumWidth)
        }
    }

    /// A column's content on a clear background, so that a column left
    /// empty, as a client's row leaves its repositories, keeps its width: a
    /// frame around an `EmptyView` takes no space, which moved the client's
    /// times under the next columns.
    private func cell(_ content: some View, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            Color.clear
            content
        }
    }
}

#if DEBUG
#Preview("Projects") {
    ProjectsScreen(model: PreviewData.model(), navigator: Navigator(.projects))
        .frame(width: 1400, height: 700)
        .background(Theme.background)
}

#Preview("Projects, Narrowest Window") {
    // The wide layout's least width, where the table scrolls sideways.
    ProjectsScreen(model: PreviewData.model(), navigator: Navigator(.projects))
        .frame(width: AdaptiveRoot<EmptyView, EmptyView>.wideWidth, height: 700)
        .background(Theme.background)
}
#endif

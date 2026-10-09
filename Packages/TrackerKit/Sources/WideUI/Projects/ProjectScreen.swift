import SwiftUI
import TrackerCore
import TrackerKit

/// A project's page: its time this week, this month and in all, its last
/// twelve weeks day by day, its tags with the issues they refer to by
/// repository, and its settings beside them.
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
    @Environment(\.undoManager) private var undoManager
    @Environment(\.commandSidebarShown) private var commandSidebarShown

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
                                WeekDays(model: model, projectID: projectID, tint: ProjectTint(hex: project.color)) {
                                    navigator.go(.month(model.today))
                                }
                                tags(overview, project: project)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                    }
                    if !commandSidebarShown {
                        ProjectSettingsPanel(model: model, project: project, navigator: navigator)
                            .frame(width: Sidebar.width)
                    }
                }
            }
            .onAppear(perform: load)
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
            KeyHint("⌘[", "back")
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 28)
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

/// A project's last twelve weeks, a row of days each, with each day's time
/// as a bar and the week's total.
struct WeekDays: View {
    let model: AppModel
    let projectID: UUID
    let tint: ProjectTint
    let openMonth: () -> Void

    var body: some View {
        let today = model.today
        let thisWeek = ReportPeriod.week.range(containing: today, firstWeekday: model.firstWeekday)
        let first = thisWeek.lowerBound.adding(days: -77)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 12 weeks").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.amber).frame(width: 8, height: 8)
                    Text("over 12 hours")
                }
                Button("Open in Month ›", action: openMonth)
                    .linkButton()
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            HStack(spacing: 4) {
                Text("").frame(width: 52)
                ForEach(0..<7, id: \.self) { offset in
                    Text(Format.weekday(thisWeek.lowerBound.adding(days: offset)).prefix(1))
                        .frame(maxWidth: .infinity)
                }
                Text("Week").frame(width: 72, alignment: .trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.text3)
            ForEach(0..<12, id: \.self) { index in
                let start = first.adding(days: index * 7)
                let days = (0..<7).map { start.adding(days: $0) }
                let times = days.map { model.dayTotals.projects(on: $0, now: model.now)[projectID] ?? 0 }
                let total = times.reduce(0, +)
                HStack(spacing: 4) {
                    Text(Format.monthDay(start))
                        .foregroundStyle(index == 11 ? Theme.text : Theme.text3)
                        .frame(width: 52, alignment: .leading)
                    ForEach(0..<7, id: \.self) { offset in
                        let day = days[offset]
                        let time = times[offset]
                        ProjectDayCell(day: day, time: time, today: today, tint: tint, barHeight: 20, sideInset: 5, bottomInset: 3)
                            .frame(height: 26)
                            .help("\(Format.longDay(day)), \(time > 0 ? Format.duration(time) : "no time")")
                    }
                    Text(total > 0 ? Format.duration(total) : "—")
                        .monospacedDigit()
                        .foregroundStyle(total > ChartScale.longWeek ? Theme.amberText : (total > 0 ? Theme.text : Theme.text3))
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 11.5))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }
}

/// A project's settings: name, client, color, repositories, calendar, and
/// archiving, merging or deleting it.
struct ProjectSettingsPanel: View {
    let model: AppModel
    let project: Project
    let navigator: Navigator
    @State private var name = ""
    @State private var repository = ""
    @State private var repositoryError = false
    @State private var mergeTarget: Project?
    @State private var confirmingDelete = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.system(size: 14, weight: .semibold))
                field("Name") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(rename)
                }
                field("Client") {
                    Picker("Client", selection: Binding(
                        get: { project.clientID },
                        set: { clientID in
                            model.updateProject(project.id, actionName: "Change Client", undoManager: undoManager) { $0.clientID = clientID }
                        }
                    )) {
                        ForEach(model.ledger.clientChoices(forProject: project.id)) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                        Divider()
                        Text("No client").tag(UUID?.none)
                    }
                    .labelsHidden()
                }
                field("Color") {
                    let users = colorUsers
                    HStack(spacing: 8) {
                        ForEach(Palette.colors, id: \.self) { hex in
                            let help = colorHelp(hex, users: users[hex] ?? [])
                            Button {
                                model.updateProject(project.id, actionName: "Change Color", undoManager: undoManager) { $0.color = hex }
                            } label: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ProjectTint(hex: hex).ink)
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        if project.color.uppercased() == hex {
                                            RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.text, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(help)
                            .accessibilityLabel(Text(help))
                            .accessibilityAddTraits(project.color.uppercased() == hex ? .isSelected : [])
                        }
                    }
                }
                repositories
                calendar
                actions
            }
            .padding(22)
            .disabled(model.isReadOnly)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .onAppear { name = project.name }
        .onChange(of: project.name) { name = project.name }
    }

    private func field<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text2)
            content()
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The names of the other projects in pickers, by their color.
    private var colorUsers: [String: [String]] {
        Dictionary(grouping: model.ledger.pickerProjects().filter { $0.id != project.id }) { $0.color.uppercased() }
            .mapValues { $0.map(\.name) }
    }

    /// A color's name, and the other projects that use it.
    private func colorHelp(_ hex: String, users: [String]) -> String {
        users.isEmpty ? Palette.name(of: hex) : "\(Palette.name(of: hex)), used by \(users.formatted(.list(type: .and)))"
    }

    private func rename() {
        model.renameProject(project.id, to: name, undoManager: undoManager)
    }

    private var repositories: some View {
        field("GitHub repositories", footer: "#123 refers to an issue in the first repository.") {
            VStack(spacing: 0) {
                ForEach(Array(project.repositories.enumerated()), id: \.offset) { index, address in
                    let repository = GitHub.Repository(address)
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(Theme.text3)
                        Text(repository?.title ?? address)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if index == 0 {
                            Text("#123")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.tag)
                        } else {
                            Button("Make first") {
                                model.makeFirstRepository(address, ofProject: project.id, undoManager: undoManager)
                            }
                            .linkButton()
                            .font(.system(size: 11.5))
                        }
                        Button {
                            model.removeRepository(address, fromProject: project.id, undoManager: undoManager)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(repository?.title ?? address)"))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                HStack(spacing: 8) {
                    TextField("owner/repo or URL", text: $repository)
                        .textFieldStyle(.plain)
                        .onSubmit(addRepository)
                    Button("Add", action: addRepository)
                        .disabled(repository.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 34)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(repositoryError ? Theme.amber : Theme.strongLine))
        }
    }

    private func addRepository() {
        repositoryError = !model.addRepository(repository, toProject: project.id, undoManager: undoManager)
        if !repositoryError {
            repository = ""
        }
    }

    private var calendar: some View {
        field("Calendar on this \(deviceName)") {
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow Access to Calendars…") {
                    Task { await model.requestCalendarAccess() }
                }
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("No access to calendars.")
                        .foregroundStyle(Theme.text2)
                    Button("Open Privacy & Security") {
                        if let url = calendarPrivacySettings {
                            openURL(url)
                        }
                    }
                }
                .font(.system(size: 12))
            case .restricted:
                Text("Calendar access is restricted on this \(deviceName).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            case .granted:
                Picker("Calendar", selection: Binding(
                    get: { model.linkedCalendar(ofProject: project.id)?.id },
                    set: { model.setCalendar($0, forProject: project.id) }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(model.calendars) { info in
                        Text(calendarLabel(info)).tag(String?.some(info.id))
                    }
                }
                .labelsHidden()
            }
        }
        .onAppear { model.refreshCalendars() }
    }

    /// Such as "Work · Exchange (linked to Website)".
    private func calendarLabel(_ info: CalendarInfo) -> String {
        let account = info.account.isEmpty ? "" : " · \(info.account)"
        guard let other = model.linkedProject(of: info.id), other != project.id else { return info.title + account }
        return "\(info.title)\(account) (linked to \(model.ledger.projectTitle(other)))"
    }

    private var actions: some View {
        let hasEntries = model.ledger.hasEntries(project: project.id)
        let others = model.ledger.mergeTargets(forProject: project.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(project.archived ? "Unarchive" : "Archive") {
                    model.updateProject(project.id, actionName: project.archived ? "Unarchive Project" : "Archive Project", undoManager: undoManager) {
                        $0.archived.toggle()
                    }
                }
                Menu("Merge into…") {
                    ForEach(others) { other in
                        Button(model.ledger.projectTitle(other.id)) {
                            mergeTarget = other
                        }
                    }
                }
                .plainMenu()
                .fixedSize()
                .disabled(others.isEmpty)
                Button("Delete…") {
                    confirmingDelete = true
                }
                .disabled(hasEntries)
            }
            .buttonStyle(ChoiceButtonStyle(compact: true))
            if hasEntries {
                Text("A project with entries can't be deleted.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(
            "Merge “\(project.name)” into “\(mergeTarget.map { model.ledger.projectTitle($0.id) } ?? "")”?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            presenting: mergeTarget
        ) { target in
            Button("Merge") {
                if (try? model.mergeProject(project.id, into: target.id, undoManager: undoManager)) != nil {
                    navigator.go(.project(target.id))
                }
            }
        } message: { target in
            Text("Its entries move to “\(target.name)”, and “\(project.name)” is deleted.")
        }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if (try? model.deleteProject(project.id, undoManager: undoManager)) != nil {
                    navigator.go(.projects)
                }
            }
        }
    }
}

#if os(macOS)
import AppKit
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
                    ProjectSettingsPanel(model: model, project: project, navigator: navigator)
                        .frame(width: 380)
                }
            }
            .onAppear(perform: load)
            .onChange(of: model.revision) { load() }
            .onChange(of: model.now) {
                if overview?.isRunning == true {
                    load()
                }
            }
            .onChange(of: projectID) { load() }
            .confirmationDialog(
                "Remove “\(removing?.name ?? "")” from every entry of \(project.name)?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                presenting: removing
            ) { tag in
                Button("Remove", role: .destructive) {
                    model.removeTag(tag.name, fromProject: projectID, undoManager: undoManager)
                    selectedTag = nil
                }
            }
        } else {
            Text("This project is gone.")
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() {
        overview = ProjectOverview(
            projects: [projectID],
            ledger: model.ledger,
            resolved: model.resolved,
            today: model.today,
            firstWeekday: model.firstWeekday,
            now: model.now
        )
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
                    model.startTimer(Combination(projectID: projectID, tags: []), undoManager: undoManager)
                }
                .buttonStyle(ChoiceButtonStyle(compact: true))
                .disabled(model.isReadOnly)
                .help(model.running == nil ? "Start a timer for \(project.name)" : "Stop the running timer and start one for \(project.name)")
            }
        }
    }

    private func figures(_ overview: ProjectOverview) -> some View {
        let running = model.running.flatMap { $0.entry.projectID == projectID ? $0 : nil }
        let longCorrection = monthCorrection
        return HStack(spacing: 1) {
            figure("This week", Format.duration(overview.thisWeek), running.map { "\(Format.duration(model.duration(of: $0))) of it running now" } ?? " ")
            VStack(alignment: .leading, spacing: 4) {
                Text("This month")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                Text(Format.duration(overview.thisMonth))
                    .font(.system(size: 24, weight: .medium))
                    .monospacedDigit()
                if let longCorrection {
                    HStack(spacing: 4) {
                        Text(longCorrection.text)
                        Button("correct it") {
                            navigator.go(.week(longCorrection.day))
                        }
                        .buttonStyle(.link)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amberText)
                } else {
                    Text(" ").font(.system(size: 12))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            figure(
                "All time",
                Format.duration(overview.total),
                overview.firstDay.map { "since \(Format.longDay($0)) · \(overview.entryCount) \(overview.entryCount == 1 ? "entry" : "entries")" } ?? " "
            )
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    /// A timer this month that ran long, as "19:25 is Thursday's overnight
    /// timer".
    private var monthCorrection: (text: String, day: LocalDate)? {
        let month = ReportPeriod.month.range(containing: model.today, firstWeekday: model.firstWeekday)
        for correction in Corrections.find(on: month, ledger: model.ledger, resolved: model.resolved, timeZone: model.environment.timeZone(), now: model.now) {
            if case let .ranLong(id, overnight) = correction.kind, let entry = model.ledger.entries[id], entry.projectID == projectID {
                let length = Format.duration(entry.start.distance(to: entry.end ?? model.now))
                return ("\(length) is \(Format.weekday(entry.day))'s \(overnight ? "overnight " : "")timer ·", correction.day)
            }
        }
        return nil
    }

    private func figure(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Text(value)
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
    }

    // MARK: Tags

    private func tags(_ overview: ProjectOverview, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tags").font(.system(size: 14, weight: .semibold))
                    + Text(" · all time").foregroundColor(Theme.text3)
                Spacer()
                Text("Select one to rename it, merge it into another or remove it")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            if overview.repositories.isEmpty && overview.tags.isEmpty {
                Text("No tags yet. Type them with a #, as in book #227.")
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
                    renameRow(tag, project: project)
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
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.fill)
                                Capsule()
                                    .fill(ProjectTint(hex: project.color).bar)
                                    .frame(width: geometry.size.width * CGFloat(tag.milliseconds) / CGFloat(max(highest, 1)))
                            }
                        }
                        .frame(height: 5)
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
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    /// The selected tag with a field for its new name, which merges it into
    /// another of the project's tags when it's that tag's name.
    private func renameRow(_ tag: ProjectOverview.Tag, project: Project) -> some View {
        let others = (overview?.tagNames ?? []).filter { !Tags.same($0, tag.name) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("New name for the tag \(tag.name)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($renaming)
                    .onSubmit { rename(tag, to: newName) }
                    .onExitCommand { selectedTag = nil }
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
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(others.isEmpty)
                .help("Merge it into another of \(project.name)'s tags")
                Button {
                    removing = tag
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Remove the tag from \(project.name)'s entries")
            }
            Text("Renames it on \(tag.count) \(project.name) \(tag.count == 1 ? "entry" : "entries"). The name of another of its tags merges the two. ⏎ rename, esc keep it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentFill))
        .disabled(model.isReadOnly)
    }

    /// Renames the tag to the new name, spelled as the project's tag of that
    /// name if it has one.
    private func rename(_ tag: ProjectOverview.Tag, to name: String) {
        defer { selectedTag = nil }
        guard let cleaned = Tags.normalize([name]).first, cleaned != tag.name else { return }
        let existing = (overview?.tagNames ?? []).first { Tags.same($0, cleaned) && !Tags.same($0, tag.name) }
        model.renameTag(tag.name, to: existing ?? cleaned, inProject: projectID, undoManager: undoManager)
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
        let thisWeek = ReportPeriod.week.range(containing: model.today, firstWeekday: model.firstWeekday)
        let first = thisWeek.lowerBound.adding(days: -77)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 12 weeks").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(tint.bar).frame(width: 8, height: 8)
                    Text("hours that day")
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.amber).frame(width: 8, height: 8)
                    Text("more than 12 hours")
                }
                Button("Open in Month ›", action: openMonth)
                    .buttonStyle(.link)
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
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day > model.today ? Color.clear : (day.weekday == 1 || day.weekday == 7 ? Theme.weekendCell : Theme.cell))
                                .overlay {
                                    if day > model.today {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.strongLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                    } else if day == model.today {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1.5)
                                    }
                                }
                            if time > 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(time > Corrections.longest ? Theme.amber : tint.bar)
                                    .frame(height: max(2, CGFloat(min(time, 37_800_000)) / 37_800_000 * 20))
                                    .padding(.horizontal, 5)
                                    .padding(.bottom, 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .help("\(Format.longDay(day)), \(time > 0 ? Format.duration(time) : "no time")")
                    }
                    Text(total > 0 ? Format.duration(total) : "—")
                        .monospacedDigit()
                        .foregroundStyle(total > 50 * 3_600_000 ? Theme.amberText : (total > 0 ? Theme.text : Theme.text3))
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

    static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings").font(.system(size: 14, weight: .semibold))
                    Text("Saved in projects.json, so every device has them")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                }
                field("Name") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(rename)
                }
                field("Client", footer: "Its history moves with it, past reports included.") {
                    Picker("Client", selection: Binding(
                        get: { project.clientID },
                        set: { clientID in
                            model.updateProject(project.id, actionName: "Change Client", undoManager: undoManager) { $0.clientID = clientID }
                        }
                    )) {
                        ForEach(model.ledger.liveClients().filter { !$0.archived || $0.id == project.clientID }) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                        Divider()
                        Text("No client").tag(UUID?.none)
                    }
                    .labelsHidden()
                }
                field("Color") {
                    HStack(spacing: 8) {
                        ForEach(Palette.colors, id: \.self) { hex in
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
                            .help(colorHelp(hex))
                            .accessibilityLabel(Text(colorHelp(hex)))
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
        .onChange(of: project.id) { name = project.name }
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

    private func colorHelp(_ hex: String) -> String {
        let users = model.ledger.pickerProjects().filter { $0.id != project.id && $0.color.uppercased() == hex }.map(\.name)
        return users.isEmpty ? Palette.name(of: hex) : "\(Palette.name(of: hex)), used by \(users.formatted(.list(type: .and)))"
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.name else { return }
        model.updateProject(project.id, actionName: "Rename Project", undoManager: undoManager) { $0.name = trimmed }
    }

    private var repositories: some View {
        field("GitHub repositories", footer: "A bare #123 means an issue in the first one. Making another the first rewrites tags so each still points at the same issue.") {
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
                            .buttonStyle(.link)
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
                    TextField("owner/name, or paste its address", text: $repository)
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
        field("Calendar · this Mac only", footer: "Its events show up in the week as corrections until you log them.") {
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow Access to Calendars…") {
                    Task { await model.requestCalendarAccess() }
                }
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time Tracker isn't allowed to read your calendars.")
                        .foregroundStyle(Theme.text2)
                    Button("Open Privacy & Security") {
                        NSWorkspace.shared.open(Self.privacySettings)
                    }
                }
                .font(.system(size: 12))
            case .restricted:
                Text("Reading calendars isn't allowed on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            case .granted:
                Picker("Calendar", selection: Binding(
                    get: { model.linkedCalendar(ofProject: project.id)?.id },
                    set: { model.setCalendar($0, forProject: project.id) }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(calendars) { info in
                        Text(calendarLabel(info)).tag(String?.some(info.id))
                    }
                }
                .labelsHidden()
            }
        }
        .onAppear { model.refreshCalendars() }
    }

    /// This Mac's calendars by account, then title.
    private var calendars: [CalendarInfo] {
        model.calendars.sorted { a, b in
            a.account != b.account
                ? a.account.localizedStandardCompare(b.account) == .orderedAscending
                : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Such as "Northbridge · Exchange (linked to Harbor)".
    private func calendarLabel(_ info: CalendarInfo) -> String {
        let account = info.account.isEmpty ? "" : " · \(info.account)"
        guard let other = model.linkedProject(of: info.id), other != project.id else { return info.title + account }
        return "\(info.title)\(account) (linked to \(model.ledger.projectTitle(other)))"
    }

    private var actions: some View {
        let entries = model.resolved.filter { $0.entry.projectID == project.id }.count
        let others = model.ledger.projects.values
            .filter { !$0.isDeleted && $0.id != project.id }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
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
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(others.isEmpty)
                Button("Delete…") {
                    confirmingDelete = true
                }
                .disabled(entries > 0)
            }
            .buttonStyle(ChoiceButtonStyle(compact: true))
            Text(entries > 0
                ? "It has \(entries) \(entries == 1 ? "entry" : "entries"), so it can be archived or merged but not deleted. Archived projects leave the pickers and stay in reports."
                : "It has no entries, so it can be deleted.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
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
            Text("Every entry of “\(project.name)” moves to “\(target.name)”, and “\(project.name)” is deleted.")
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
#endif

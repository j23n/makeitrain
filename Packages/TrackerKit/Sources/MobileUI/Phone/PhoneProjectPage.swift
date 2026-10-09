#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// A project's page: its running timer, its time this week, this month
/// and in all, its last twelve weeks day by day, and its tags by
/// repository. Edit opens its settings.
struct PhoneProjectPage: View {
    let model: AppModel
    let router: PhoneRouter
    let projectID: UUID
    @State private var overview: ProjectOverview?
    @State private var editing = false
    @State private var chosenTag: ProjectOverview.Tag?
    @State private var renaming: ProjectOverview.Tag?
    @State private var newName = ""
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL

    private var project: Project? {
        model.ledger.projects[projectID].flatMap { $0.isDeleted ? nil : $0 }
    }

    var body: some View {
        Group {
            if let project {
                page(project)
            } else {
                Text("This project was deleted.")
                    .foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .fontWeight(.semibold)
                    .disabled(project == nil)
            }
        }
        .sheet(isPresented: $editing) {
            if let project {
                PhoneProjectSettings(model: model, project: project) { merged in
                    if let merged {
                        router.projectsPath = [.project(merged)]
                    } else {
                        router.projectsPath = []
                    }
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
    }

    private func load() {
        overview = ProjectOverview(project: projectID, model: model)
    }

    private func page(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ProjectTint(hex: project.color).ink)
                            .frame(width: 20, height: 20)
                        Text(project.name)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(2)
                    }
                    Text(model.ledger.client(forProject: projectID)?.name ?? "No client")
                        .foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 4)
                timer(project)
                if let overview {
                    figures(overview)
                    PhoneProjectWeeks(model: model, projectID: projectID, tint: ProjectTint(hex: project.color)) {
                        router.month.show(ReportPeriod.month.range(containing: model.today, firstWeekday: model.firstWeekday), period: .month)
                        router.month.projects = [projectID]
                        router.tab = .month
                    }
                    tags(overview, project: project)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .confirmationDialog(
            chosenTag?.name ?? "",
            isPresented: Binding(get: { chosenTag != nil }, set: { if !$0 { chosenTag = nil } }),
            titleVisibility: .visible,
            presenting: chosenTag
        ) { tag in
            if let url = tag.url {
                Button("Open on GitHub") { openURL(url) }
            }
            Button("Rename or Merge…") {
                newName = tag.name
                renaming = tag
            }
            Button("Remove from All Entries", role: .destructive) {
                model.removeTag(tag.name, fromProject: projectID, undoManager: undoManager)
            }
        } message: { tag in
            Text("\(Format.duration(tag.milliseconds)) on \(tag.count) \(tag.count == 1 ? "entry" : "entries")")
        }
        .alert(
            "Rename \(renaming?.name ?? "")",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { tag in
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") {
                model.renameTag(tag.name, to: newName, inProject: projectID, undoManager: undoManager)
            }
            Button("Cancel", role: .cancel) {}
        } message: { tag in
            Text("Renames it on \(tag.count) \(tag.count == 1 ? "entry" : "entries"). Another tag's name merges the two.")
        }
    }

    /// The running timer with Stop, or Start.
    @ViewBuilder
    private func timer(_ project: Project) -> some View {
        if let running = model.running, running.entry.projectID == projectID {
            HStack(spacing: 9) {
                Circle().fill(Theme.now).frame(width: 7, height: 7)
                Text(Format.duration(model.duration(of: running)))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(([running.entry.note] + running.entry.tags).filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    Text("Stop")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.inverseText)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.inverse))
                }
                .buttonStyle(.plain)
                .disabled(model.isReadOnly)
            }
            .font(.system(size: 15))
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 15).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.line))
        } else if !project.archived {
            Button {
                model.startTimer(EntryDraft(projectID: projectID), undoManager: undoManager)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(model.running == nil ? "Start \(project.name)" : "Switch to \(project.name)")
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Theme.text)
                .background(RoundedRectangle(cornerRadius: 15).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.line))
            }
            .buttonStyle(.plain)
            .disabled(model.isReadOnly)
        }
    }

    private func figures(_ overview: ProjectOverview) -> some View {
        HStack(spacing: 1) {
            figure("This week", overview.thisWeek, marked: false)
            figure("This month", overview.thisMonth, marked: overview.longTimer != nil)
            figure("All time", overview.total, marked: false)
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }

    private func figure(_ label: String, _ milliseconds: Int64, marked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(label)
                if marked {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                        .accessibilityLabel(Text("includes a timer that ran long"))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            Text(Format.duration(milliseconds))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
    }

    // MARK: Tags

    @ViewBuilder
    private func tags(_ overview: ProjectOverview, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 2)
            if overview.repositories.isEmpty && overview.tags.isEmpty {
                Text("No tags yet. Type them with #, as in #design.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 2)
            }
            ForEach(overview.repositories) { repository in
                tagGroup(repository.title, detail: "\(repository.issues.count) \(repository.issues.count == 1 ? "issue" : "issues")", tags: repository.issues, tint: ProjectTint(hex: project.color))
            }
            if !overview.tags.isEmpty {
                tagGroup("Other tags", detail: "\(overview.tags.count)", tags: overview.tags, tint: ProjectTint(hex: project.color))
            }
        }
    }

    private func tagGroup(_ title: String, detail: String, tags: [ProjectOverview.Tag], tint: ProjectTint) -> some View {
        let highest = tags.map(\.milliseconds).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            ForEach(tags.prefix(12)) { tag in
                Button {
                    chosenTag = tag
                } label: {
                    HStack(spacing: 10) {
                        Text(tag.number.map { "#\($0)" } ?? tag.name)
                            .foregroundStyle(tag.url == nil ? Theme.text : Theme.tag)
                            .lineLimit(1)
                            .frame(width: tag.number == nil ? 104 : 52, alignment: .leading)
                        ShareBar(tag.milliseconds, of: highest, color: tint.bar, height: 5)
                        Text(Format.duration(tag.milliseconds))
                            .monospacedDigit()
                            .frame(width: 78, alignment: .trailing)
                    }
                    .font(.system(size: 14))
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if tags.count > 12 {
                Text("and \(tags.count - 12) more")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }
}

/// A project's last twelve weeks, a row of days each, with each day's time
/// as a bar and the week's total.
struct PhoneProjectWeeks: View {
    let model: AppModel
    let projectID: UUID
    let tint: ProjectTint
    let openMonth: () -> Void

    var body: some View {
        let today = model.today
        let thisWeek = ReportPeriod.week.range(containing: today, firstWeekday: model.firstWeekday)
        let first = thisWeek.lowerBound.adding(days: -77)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 12 weeks")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Open in Month", action: openMonth)
                    .font(.system(size: 13.5))
            }
            .padding(.horizontal, 2)
            VStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    let start = first.adding(days: index * 7)
                    let days = (0..<7).map { start.adding(days: $0) }
                    let times = days.map { model.dayTotals.projects(on: $0, now: model.now)[projectID] ?? 0 }
                    let total = times.reduce(0, +)
                    HStack(spacing: 4) {
                        Text(Format.monthDay(start))
                            .foregroundStyle(index == 11 ? Theme.text : Theme.text3)
                            .lineLimit(1)
                            .frame(width: 44, alignment: .leading)
                        ForEach(0..<7, id: \.self) { offset in
                            ProjectDayCell(day: days[offset], time: times[offset], today: today, tint: tint, barHeight: 13, sideInset: 2, bottomInset: 2)
                        }
                        Text(total > 0 ? Format.duration(total) : "—")
                            .monospacedDigit()
                            .foregroundStyle(total > ChartScale.longWeek ? Theme.amberText : (total > 0 ? Theme.text : Theme.text3))
                            .lineLimit(1)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.system(size: 11.5))
                    .frame(height: 17)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Week of \(Format.monthDay(start)), \(total > 0 ? Format.duration(total) : "no time")"))
                }
            }
        }
    }
}

/// A project's settings: name, client, color, GitHub repositories, the
/// calendar on this iPhone, and archiving, merging or deleting it.
struct PhoneProjectSettings: View {
    let model: AppModel
    let project: Project
    /// After a merge, the project it went into; after a delete, nil.
    let gone: (UUID?) -> Void
    @State private var name = ""
    @State private var mergeTarget: Project?
    @State private var confirmingDelete = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let hasEntries = model.ledger.hasEntries(project: project.id)
        let others = model.ledger.mergeTargets(forProject: project.id)
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit(rename)
                    Picker("Client", selection: Binding(
                        get: { project.clientID },
                        set: { clientID in
                            model.updateProject(project.id, actionName: "Change Client", undoManager: undoManager) { $0.clientID = clientID }
                        }
                    )) {
                        Text("No client").tag(UUID?.none)
                        ForEach(model.ledger.clientChoices(forProject: project.id)) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(Palette.colors, id: \.self) { hex in
                            let chosen = project.color.uppercased() == hex
                            Button {
                                model.updateProject(project.id, actionName: "Change Color", undoManager: undoManager) { $0.color = hex }
                            } label: {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(ProjectTint(hex: hex).ink)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if chosen {
                                            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.text, lineWidth: 2.5)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(Palette.name(of: hex)))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                MobileRepositoriesSection(model: model, project: project)
                MobileProjectCalendarSection(model: model, project: project)
                Section {
                    Toggle("Archived", isOn: Binding(
                        get: { project.archived },
                        set: { archived in
                            model.updateProject(project.id, actionName: archived ? "Archive Project" : "Unarchive Project", undoManager: undoManager) { $0.archived = archived }
                        }
                    ))
                    Menu("Merge Into…") {
                        ForEach(others) { other in
                            Button(model.ledger.projectTitle(other.id)) {
                                mergeTarget = other
                            }
                        }
                    }
                    .disabled(others.isEmpty)
                    Button("Delete…", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(hasEntries)
                } footer: {
                    if hasEntries {
                        Text("A project with entries can't be deleted.")
                    }
                }
            }
            .disabled(model.isReadOnly)
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        rename()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Merge “\(project.name)” into “\(mergeTarget.map { model.ledger.projectTitle($0.id) } ?? "")”?",
                isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
                titleVisibility: .visible,
                presenting: mergeTarget
            ) { target in
                Button("Merge") {
                    if (try? model.mergeProject(project.id, into: target.id, undoManager: undoManager)) != nil {
                        dismiss()
                        gone(target.id)
                    }
                }
            } message: { target in
                Text("Its entries move to “\(target.name)”, and “\(project.name)” is deleted.")
            }
            .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if (try? model.deleteProject(project.id, undoManager: undoManager)) != nil {
                        dismiss()
                        gone(nil)
                    }
                }
            }
        }
        .onAppear { name = project.name }
    }

    private func rename() {
        model.renameProject(project.id, to: name, undoManager: undoManager)
    }
}
#endif

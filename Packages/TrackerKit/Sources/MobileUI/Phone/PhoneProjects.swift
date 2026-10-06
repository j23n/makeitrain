#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// Clients and their projects: each project's repositories and calendar,
/// its last twelve weeks and its time this week, then the entries without
/// a project and the archived ones. A project opens its page.
struct PhoneProjects: View {
    let model: AppModel
    let router: PhoneRouter
    @State private var filter = ""
    @State private var stats: ProjectStats?

    var body: some View {
        NavigationStack(path: Binding(get: { router.projectsPath }, set: { router.projectsPath = $0 })) {
            list
                .navigationTitle("Projects")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PhoneProjectRoute.self) { route in
                    switch route {
                    case let .project(id):
                        PhoneProjectPage(model: model, router: router, projectID: id)
                    case .archived:
                        PhoneArchivedProjects(model: model, stats: stats ?? ProjectStats(model: model))
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            PhoneCommandBar(model: model, placeholder: "new project, or switch", open: { router.openCommandLine() })
        }
        .onAppear {
            stats = ProjectStats(model: model)
        }
        .onChange(of: model.revision) {
            stats = ProjectStats(model: model)
        }
    }

    private var list: some View {
        let tree = ProjectTree(ledger: model.ledger)
        let figures = stats ?? ProjectStats(model: model)
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 2) {
                    Text("Projects")
                        .font(.system(size: 30, weight: .bold))
                    Spacer()
                    Button {
                        router.showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Settings"))
                    Button {
                        model.request = .command("new project ")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(model.isReadOnly)
                    .accessibilityLabel(Text("New project"))
                }
                .padding(.leading, 4)
                filterField
                    .padding(.bottom, 12)
                let clients = tree.clients.filter { !visible($0.projects).isEmpty }
                ForEach(clients) { branch in
                    let projects = visible(branch.projects)
                    section(branch.client.name, showsWeek: branch.id == clients.first?.id) {
                        ForEach(projects) { project in
                            row(project, figures: figures, divided: project.id != projects.first?.id)
                        }
                    }
                }
                let unfiled = visible(tree.unfiled)
                let unassigned = figures[nil]
                if !unfiled.isEmpty || (unassigned.entryCount > 0 && filter.isEmpty) {
                    section("No client", showsWeek: clients.isEmpty) {
                        ForEach(unfiled) { project in
                            row(project, figures: figures, divided: project.id != unfiled.first?.id)
                        }
                        if unassigned.entryCount > 0, filter.isEmpty {
                            unassignedRow(unassigned, divided: !unfiled.isEmpty)
                        }
                    }
                }
                let archived = tree.archivedProjects.count + tree.archivedClients.reduce(0) { $0 + $1.projects.count }
                if archived > 0, filter.isEmpty {
                    Button {
                        router.projectsPath.append(.archived)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(Theme.text2)
                            Text("Archived")
                            Spacer()
                            Text("\(archived)")
                                .foregroundStyle(Theme.text3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                        }
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.text3)
            TextField("Filter", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear the filter"))
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.fill))
    }

    private func section<Content: View>(_ title: String, showsWeek: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .tracking(0.6)
                Spacer()
                if showsWeek {
                    Text("this week")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
        }
        .padding(.top, 6)
    }

    private func row(_ project: Project, figures: ProjectStats, divided: Bool) -> some View {
        let row = figures[project.id]
        let running = model.running?.entry.projectID == project.id
        return Button {
            router.projectsPath.append(.project(project.id))
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ProjectTint(hex: project.color).ink)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(project.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if running {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.now).frame(width: 6, height: 6)
                                Text("running")
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text2)
                        }
                    }
                    Text(detail(project, total: row.total))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                PhoneSparkline(values: row.weeks, tint: ProjectTint(hex: project.color))
                    .frame(width: 50, height: 20)
                Text(row.thisWeek > 0 ? Format.duration(row.thisWeek) : "—")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(row.thisWeek > 0 ? Theme.text : Theme.text3)
                    .frame(width: 52, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .font(.system(size: 15))
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
        .accessibilityLabel(Text("\(project.name)\(running ? ", running" : ""), \(row.thisWeek > 0 ? Format.duration(row.thisWeek) : "nothing") this week"))
    }

    /// "Scheduler · Libs · Northbridge calendar", or the time in all.
    private func detail(_ project: Project, total: Int64) -> String {
        var parts = project.repositories.compactMap { GitHub.Repository($0)?.name }
        if let calendar = model.linkedCalendar(ofProject: project.id) {
            parts.append("\(calendar.title) calendar")
        }
        if parts.isEmpty {
            return total > 0 ? "\(Format.duration(total)) in all" : "No time yet"
        }
        return parts.joined(separator: " · ")
    }

    private func unassignedRow(_ row: ProjectStats.Row, divided: Bool) -> some View {
        Button {
            if let latest = row.latest {
                router.showWeek(latest.entry.day, firstWeekday: model.firstWeekday)
                router.week.selectedEntry = latest.id
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(Theme.text3, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unassigned").fontWeight(.semibold)
                    if let latest = row.latest {
                        Text(latest.entry.note.isEmpty ? Format.day(latest.entry.day) : "\(latest.entry.note), \(Format.weekday(latest.entry.day))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text("Assign")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .font(.system(size: 15))
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
    }

    private func visible(_ projects: [Project]) -> [Project] {
        guard !filter.isEmpty else { return projects }
        let terms = ProjectSearch.terms(filter)
        return projects.filter { project in
            let name = (project.name + " " + (model.ledger.client(forProject: project.id)?.name ?? "")).lowercased()
            return terms.allSatisfy { name.contains($0) }
        }
    }
}

/// Twelve weeks as small bars, this week last.
struct PhoneSparkline: View {
    let values: [Int64]
    let tint: ProjectTint

    var body: some View {
        let highest = max(values.max() ?? 0, 40 * 3_600_000)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { index in
                UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1)
                    .fill(values[index] > 0 ? tint.bar : Theme.emptyBar)
                    .frame(height: values[index] > 0 ? max(2, CGFloat(values[index]) / CGFloat(highest) * 20) : 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The archived projects, and the projects of archived clients.
struct PhoneArchivedProjects: View {
    let model: AppModel
    let stats: ProjectStats
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let tree = ProjectTree(ledger: model.ledger)
        let projects = tree.archivedProjects + tree.archivedClients.flatMap(\.projects)
        List {
            ForEach(projects) { project in
                NavigationLink(value: PhoneProjectRoute.project(project.id)) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ProjectTint(hex: project.color).ink)
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.ledger.projectTitle(project.id))
                            Text("\(Format.duration(stats[project.id].total)) in all")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
                .swipeActions {
                    if project.archived {
                        Button("Unarchive") {
                            model.updateProject(project.id, actionName: "Unarchive Project", undoManager: undoManager) { $0.archived = false }
                        }
                        .tint(Theme.accent)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

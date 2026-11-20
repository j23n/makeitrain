import SwiftUI
import TrackerCore
import TrackerKit

/// A project's settings: name, client, color, repositories, the calendar on
/// this device, and archiving, merging or deleting it. The wide layout shows
/// them in a column beside the project's page, and the narrow one in a sheet
/// over it, at touch size.
struct ProjectSettingsPanel: View {
    let model: AppModel
    let project: Project
    /// Whether it's the narrow layout's, at touch size.
    var compact = false
    /// After a merge, the project it went into; after a delete, nil.
    let gone: (UUID?) -> Void
    @State private var name = ""
    @State private var repository = ""
    @State private var repositoryError = false
    @State private var mergeTarget: Project?
    @State private var confirmingDelete = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL

    private var swatch: CGFloat { compact ? 30 : 26 }
    private var rowHeight: CGFloat { compact ? 44 : 34 }
    private var smallFont: CGFloat { compact ? 14 : 12 }
    /// The size of a row's small parts, such as "Make first".
    private var detailFont: CGFloat { compact ? 13 : 11.5 }
    /// How wide a row's small buttons are to tap: a finger's width in the
    /// narrow layout.
    private var buttonWidth: CGFloat? { compact ? 44 : nil }

    var body: some View {
        if compact {
            ScrollView { content }
                .background(Theme.background)
        } else {
            ScrollView { content }
                .sidebarColumn()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact {
                Text("Settings").font(.system(size: 14, weight: .semibold))
            }
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
                                .frame(width: swatch, height: swatch)
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
        .padding(compact ? 16 : 22)
        .disabled(model.isReadOnly)
        .onAppear { name = project.name }
        .onChange(of: project.name) { name = project.name }
        .onDisappear(perform: renameIfChanged)
    }

    private func field<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: smallFont, weight: .semibold))
                .foregroundStyle(Theme.text2)
            content()
            if let footer {
                Text(footer)
                    .font(.system(size: smallFont))
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

    /// Keeps a name typed but not submitted, as when the sheet closes, while
    /// the project is still there.
    private func renameIfChanged() {
        guard name != project.name, model.ledger.projects[project.id]?.isDeleted == false else { return }
        rename()
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
                            .font(.system(size: smallFont, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if index == 0 {
                            Text("#123")
                                .font(.system(size: detailFont))
                                .foregroundStyle(Theme.tag)
                        } else {
                            Button {
                                model.makeFirstRepository(address, ofProject: project.id, undoManager: undoManager)
                            } label: {
                                Text("Make first")
                                    .frame(height: rowHeight)
                                    .contentShape(Rectangle())
                            }
                            .linkButton()
                            .font(.system(size: detailFont))
                        }
                        Button {
                            model.removeRepository(address, fromProject: project.id, undoManager: undoManager)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: compact ? 12 : 10, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                                .frame(width: buttonWidth, height: rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(repository?.title ?? address)"))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: rowHeight)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                HStack(spacing: 8) {
                    TextField("owner/repo or URL", text: $repository)
                        .textFieldStyle(.plain)
                        .onChange(of: repository) { repositoryError = false }
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                        .urlKeyboard()
                        .onSubmit(addRepository)
                    Button("Add", action: addRepository)
                        .disabled(repository.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .font(.system(size: smallFont))
                .padding(.horizontal, 10)
                .frame(height: rowHeight)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(repositoryError ? Theme.amber : Theme.strongLine))
            if repositoryError {
                Text("Not a GitHub repository. Use owner/repo or a URL.")
                    .font(.system(size: smallFont))
                    .foregroundStyle(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    Button(privacySettingsTitle) {
                        if let url = calendarPrivacySettings {
                            openURL(url)
                        }
                    }
                }
                .font(.system(size: smallFont))
            case .restricted:
                Text("Calendar access is restricted on this \(deviceName).")
                    .font(.system(size: smallFont))
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

    /// The button that opens where the system lets the app read calendars.
    private var privacySettingsTitle: String {
        #if os(macOS)
        return "Open Privacy & Security"
        #else
        return "Allow Access in Settings"
        #endif
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
                    .font(.system(size: smallFont))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
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
                    gone(target.id)
                }
            }
        } message: { target in
            Text("Its entries move to “\(target.name)”, and “\(project.name)” is deleted.")
        }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if (try? model.deleteProject(project.id, undoManager: undoManager)) != nil {
                    gone(nil)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Wide") {
    let model = PreviewData.model()
    return Group {
        if let project = model.ledger.projects[PreviewData.mobileApp] {
            ProjectSettingsPanel(model: model, project: project) { _ in }
        }
    }
    .frame(width: 320, height: 720)
}

#Preview("Narrow") {
    let model = PreviewData.model()
    return Group {
        if let project = model.ledger.projects[PreviewData.mobileApp] {
            ProjectSettingsPanel(model: model, project: project, compact: true) { _ in }
        }
    }
    .frame(width: 390, height: 760)
}
#endif

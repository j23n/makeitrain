import SwiftUI
import TrackerCore
import TrackerKit

/// A project's settings: name, client, color, contracts, repositories, the
/// calendar on this device, and archiving, merging or deleting it. The wide
/// layout shows them in a column beside the project's page; the narrow one
/// as a grouped form in a sheet over it.
struct ProjectSettingsPanel: View {
    let model: AppModel
    let project: Project
    /// Whether it's the narrow layout's form.
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

    var body: some View {
        Group {
            if compact {
                form
            } else {
                ScrollView { column }
                    .sidebarColumn()
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
        .onAppear {
            name = project.name
            model.refreshCalendars()
        }
        .onChange(of: project.name) { name = project.name }
        .onDisappear(perform: renameIfChanged)
    }

    // MARK: - Narrow: a grouped form

    private var form: some View {
        Form {
            identitySection
            colorSection
            ContractList(model: model, project: project, layout: .form)
            repositorySection
            calendarSection
            actionSection
        }
        .formStyle(.grouped)
    }

    private var identitySection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Name", text: $name)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .onSubmit(rename)
            }
            clientPicker
                .navigationPicker()
        }
        .disabled(model.isReadOnly)
    }

    private var colorSection: some View {
        Section("Color") {
            swatches(size: 30)
        }
        .disabled(model.isReadOnly)
    }

    private var repositorySection: some View {
        Section {
            ForEach(Array(project.repositories.enumerated()), id: \.offset) { index, address in
                formRepositoryRow(address, index: index)
            }
            HStack(spacing: 8) {
                repositoryField
                Button("Add", action: addRepository)
                    .disabled(repository.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(model.isReadOnly)
        } header: {
            Text("GitHub repositories")
        } footer: {
            repositoryFooter
        }
    }

    private var calendarSection: some View {
        Section("Calendar on this \(deviceName)") {
            calendarChoice
        }
        .disabled(model.isReadOnly)
    }

    private var actionSection: some View {
        let hasEntries = model.ledger.hasEntries(project: project.id)
        return Section {
            Toggle("Archived", isOn: Binding(
                get: { project.archived },
                set: { _ in toggleArchived() }
            ))
            mergeMenu
            Button("Delete Project…", role: .destructive) {
                confirmingDelete = true
            }
            .disabled(hasEntries)
        } footer: {
            if hasEntries {
                Text("A project with entries can't be deleted.")
            }
        }
        .disabled(model.isReadOnly)
    }

    // MARK: - Wide: a column beside the page

    private var column: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 14, weight: .semibold))
            field("Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(rename)
            }
            .disabled(model.isReadOnly)
            field("Client") {
                clientPicker
                    .labelsHidden()
            }
            .disabled(model.isReadOnly)
            field("Color") {
                swatches(size: 26)
            }
            .disabled(model.isReadOnly)
            ContractList(model: model, project: project, layout: .panel)
                .padding(.horizontal, -8)
            // The repositories disable their own changes, so that a link
            // still opens while the data is read-only.
            field("GitHub repositories") {
                repositoryBox
                repositoryFooter
                    .font(.system(size: 12))
            }
            field("Calendar on this \(deviceName)") {
                calendarChoice
                    .labelsHidden()
                    .font(.system(size: 12))
            }
            .disabled(model.isReadOnly)
            columnActions
                .disabled(model.isReadOnly)
        }
        .padding(22)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text2)
            content()
        }
    }

    /// The repositories in a bordered box, each linking to GitHub, with a
    /// field to add one at the end.
    private var repositoryBox: some View {
        VStack(spacing: 0) {
            ForEach(Array(project.repositories.enumerated()), id: \.offset) { index, address in
                boxRepositoryRow(address, index: index)
            }
            HStack(spacing: 8) {
                repositoryField
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                Button("Add", action: addRepository)
                    .linkButton()
                    .font(.system(size: 12, weight: .medium))
                    .disabled(repository.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .disabled(model.isReadOnly)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(repositoryError ? Theme.amber : Theme.strongLine))
    }

    /// A repository in the form: its name, "#123" on the first, and a
    /// menu, with a swipe to remove it.
    private func formRepositoryRow(_ address: String, index: Int) -> some View {
        let title = GitHub.Repository(address)?.title ?? address
        return HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if index == 0 {
                issueBadge
            }
            repositoryMoreMenu(address, index: index, title: title, systemImage: "ellipsis.circle", size: 32)
        }
        .swipeActions {
            Button("Remove", role: .destructive) {
                model.removeRepository(address, fromProject: project.id, undoManager: undoManager)
            }
            .disabled(model.isReadOnly)
        }
    }

    /// A repository in the wide layout's box: its name, linking to GitHub,
    /// "#123" on the first, and a menu.
    private func boxRepositoryRow(_ address: String, index: Int) -> some View {
        let repository = GitHub.Repository(address)
        let title = repository?.title ?? address
        return HStack(spacing: 8) {
            repositoryLink(title: title, url: repository.flatMap { URL(string: $0.address) })
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if index == 0 {
                issueBadge
            }
            repositoryMoreMenu(address, index: index, title: title, systemImage: "ellipsis", size: 20)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contextMenu { repositoryMenu(address, index: index) }
    }

    @ViewBuilder
    private func repositoryLink(title: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Text(title)
            }
            .help("Open \(title) in the browser")
        } else {
            Text(title)
        }
    }

    private func repositoryMoreMenu(_ address: String, index: Int, title: String, systemImage: String, size: CGFloat) -> some View {
        let label = Image(systemName: systemImage)
            .foregroundStyle(Theme.text3)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        return Menu {
            repositoryMenu(address, index: index)
        } label: {
            label
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More for \(title)"))
    }

    private var columnActions: some View {
        let hasEntries = model.ledger.hasEntries(project: project.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(project.archived ? "Unarchive" : "Archive", action: toggleArchived)
                mergeMenu
                    .plainMenu()
                    .fixedSize()
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
    }

    // MARK: - Shared parts

    private var clientPicker: some View {
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
    }

    private func swatches(size: CGFloat) -> some View {
        let users = colorUsers
        return HStack(spacing: 8) {
            ForEach(Palette.colors, id: \.self) { hex in
                let help = colorHelp(hex, users: users[hex] ?? [])
                Button {
                    model.updateProject(project.id, actionName: "Change Color", undoManager: undoManager) { $0.color = hex }
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ProjectTint(hex: hex).ink)
                        .frame(width: size, height: size)
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

    private func toggleArchived() {
        model.updateProject(project.id, actionName: project.archived ? "Unarchive Project" : "Archive Project", undoManager: undoManager) {
            $0.archived.toggle()
        }
    }

    private var mergeMenu: some View {
        let others = model.ledger.mergeTargets(forProject: project.id)
        return Menu("Merge Into…") {
            ForEach(others) { other in
                Button(model.ledger.projectTitle(other.id)) {
                    mergeTarget = other
                }
            }
        }
        .disabled(others.isEmpty)
    }

    // MARK: Repositories

    /// What "#123" refers to: an issue in the first repository.
    private var issueBadge: some View {
        Text("#123")
            .font(.system(size: compact ? 13 : 11.5, design: .monospaced))
            .foregroundStyle(Theme.tag)
            .help("#123 refers to an issue in this repository")
            .accessibilityLabel(Text("Issues such as #123 refer to this repository"))
    }

    @ViewBuilder
    private func repositoryMenu(_ address: String, index: Int) -> some View {
        if let url = GitHub.Repository(address).flatMap({ URL(string: $0.address) }) {
            Button("Open on GitHub") { openURL(url) }
        }
        if index > 0 {
            Button("Make First") {
                model.makeFirstRepository(address, ofProject: project.id, undoManager: undoManager)
            }
            .disabled(model.isReadOnly)
        }
        Button("Remove", role: .destructive) {
            model.removeRepository(address, fromProject: project.id, undoManager: undoManager)
        }
        .disabled(model.isReadOnly)
    }

    private var repositoryField: some View {
        TextField("owner/repo or URL", text: $repository)
            .onChange(of: repository) { repositoryError = false }
            .noAutocapitalization()
            .autocorrectionDisabled()
            .urlKeyboard()
            .onSubmit(addRepository)
    }

    @ViewBuilder
    private var repositoryFooter: some View {
        if repositoryError {
            Text("Not a GitHub repository. Use owner/repo or a URL.")
                .foregroundStyle(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
        } else if !project.repositories.isEmpty {
            Text("#123 refers to an issue in the first repository.")
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addRepository() {
        repositoryError = !model.addRepository(repository, toProject: project.id, undoManager: undoManager)
        if !repositoryError {
            repository = ""
        }
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarChoice: some View {
        switch model.calendarAccess {
        case .notDetermined:
            Button("Allow Access to Calendars…") {
                Task { await model.requestCalendarAccess() }
            }
        case .denied:
            Text("No access to calendars.")
                .foregroundStyle(Theme.text2)
            Button(privacySettingsTitle) {
                if let url = calendarPrivacySettings {
                    openURL(url)
                }
            }
        case .restricted:
            Text("Calendar access is restricted on this \(deviceName).")
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
        }
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
}

#if DEBUG
#Preview("Wide") {
    let model = PreviewData.model()
    return Group {
        if let project = model.ledger.projects[PreviewData.website] {
            ProjectSettingsPanel(model: model, project: project) { _ in }
        }
    }
    .frame(width: 380, height: 820)
}

#Preview("Narrow") {
    let model = PreviewData.model()
    return Group {
        if let project = model.ledger.projects[PreviewData.website] {
            NavigationStack {
                ProjectSettingsPanel(model: model, project: project, compact: true) { _ in }
            }
        }
    }
    .frame(width: 390, height: 760)
}
#endif

import SwiftUI
import TrackerCore
#if os(macOS)
import AppKit
#endif

// Picking a project by typing part of the client's or the project's name,
// such as "web" or "acme web" for "Acme › Website redesign". The Mac shows
// a search field over a list in a popover; iOS pushes a searchable list.

/// One row of a project picker: no project, or a project.
public enum ProjectChoice: Hashable, Identifiable, Sendable {
    case noProject
    case project(UUID)

    public init(_ projectID: UUID?) {
        self = projectID.map { .project($0) } ?? .noProject
    }

    public var id: Self { self }

    public var projectID: UUID? {
        switch self {
        case .noProject: nil
        case .project(let id): id
        }
    }

    /// What a picker lists for what's typed: "No Project" when nothing is
    /// typed or it matches, then the matching projects, best first.
    /// `current` stays listed when it matches, even if it's archived.
    public static func options(
        in ledger: Ledger,
        matching query: String,
        current: UUID?,
        offersNoProject: Bool = true,
        excluding excluded: UUID? = nil
    ) -> [ProjectChoice] {
        let projects = ledger.pickerProjects(matching: query, including: current)
            .filter { $0.id != excluded }
            .map { ProjectChoice.project($0.id) }
        return offersNoProject && ProjectSearch.matchesNoProject(query) ? [.noProject] + projects : projects
    }
}

/// A picker row's title: the project's color and title, or "No Project".
public struct ProjectChoiceLabel: View {
    let ledger: Ledger
    let choice: ProjectChoice

    public init(ledger: Ledger, choice: ProjectChoice) {
        self.ledger = ledger
        self.choice = choice
    }

    public var body: some View {
        switch choice {
        case .noProject:
            HStack(spacing: 6) {
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1)
                    .frame(width: 8, height: 8)
                Text("No Project")
                    .foregroundStyle(.secondary)
            }
        case .project(let id):
            ProjectLabel(ledger: ledger, projectID: id)
        }
    }
}

#if os(macOS)
/// A button showing the chosen project, which opens a searchable list of
/// projects in a popover.
public struct ProjectPicker: View {
    let ledger: Ledger
    @Binding var selection: UUID?
    let title: String
    @State private var choosing = false

    public init(ledger: Ledger, selection: Binding<UUID?>, title: String = "Project") {
        self.ledger = ledger
        _selection = selection
        self.title = title
    }

    public var body: some View {
        LabeledContent(title) {
            Button {
                choosing = true
            } label: {
                ProjectPickerButtonLabel(ledger: ledger, projectID: selection)
            }
            .help("Choose a project; type to search clients and projects")
            .popover(isPresented: $choosing, arrowEdge: .bottom) {
                ProjectChooser(ledger: ledger, current: ProjectChoice(selection)) { projectID in
                    choosing = false
                    selection = projectID
                } cancel: {
                    choosing = false
                }
                .frame(width: 320)
            }
        }
    }
}

/// What a project picker's button shows: the chosen project and a chevron.
public struct ProjectPickerButtonLabel: View {
    let ledger: Ledger
    let projectID: UUID?

    public init(ledger: Ledger, projectID: UUID?) {
        self.ledger = ledger
        self.projectID = projectID
    }

    public var body: some View {
        HStack(spacing: 6) {
            ProjectChoiceLabel(ledger: ledger, choice: ProjectChoice(projectID))
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
    }
}

/// A search field over a list of projects. Typing narrows the list to the
/// projects whose client or name has each word typed, the arrow keys move
/// the highlight, Return chooses it, and Escape clears the search or
/// cancels.
public struct ProjectChooser: View {
    let ledger: Ledger
    let current: ProjectChoice?
    let offersNoProject: Bool
    let excluded: UUID?
    let choose: (UUID?) -> Void
    let cancel: () -> Void
    @State private var query: String
    @State private var highlighted = 0

    /// `current` gets a checkmark; nil marks nothing, as when several
    /// entries with different projects are selected.
    public init(
        ledger: Ledger,
        current: ProjectChoice?,
        offersNoProject: Bool = true,
        excluding excluded: UUID? = nil,
        query: String = "",
        choose: @escaping (UUID?) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.ledger = ledger
        self.current = current
        self.offersNoProject = offersNoProject
        self.excluded = excluded
        self.choose = choose
        self.cancel = cancel
        _query = State(initialValue: query)
    }

    public var body: some View {
        let options = ProjectChoice.options(
            in: ledger,
            matching: query,
            current: current?.projectID,
            offersNoProject: offersNoProject,
            excluding: excluded
        )
        VStack(spacing: 0) {
            KeyboardSearchField(
                text: $query,
                placeholder: "Search clients and projects",
                onMove: { step in
                    highlighted = min(max(highlighted + step, 0), max(options.count - 1, 0))
                },
                onSubmit: {
                    if options.indices.contains(highlighted) {
                        choose(options[highlighted].projectID)
                    }
                },
                onCancel: {
                    if query.isEmpty {
                        cancel()
                    } else {
                        query = ""
                    }
                }
            )
            .padding(8)
            Divider()
            if options.isEmpty {
                Text("No matching projects")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                                ProjectChooserRow(
                                    ledger: ledger,
                                    choice: option,
                                    isCurrent: option == current,
                                    isHighlighted: index == highlighted
                                )
                                .id(index)
                                .onHover { inside in
                                    if inside {
                                        highlighted = index
                                    }
                                }
                                .onTapGesture {
                                    choose(option.projectID)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: min(CGFloat(options.count) * ProjectChooserRow.height + 8, 300))
                    .onChange(of: highlighted) { _, index in
                        proxy.scrollTo(index)
                    }
                }
            }
        }
        .onChange(of: query) { _, _ in
            highlighted = 0
        }
        .onAppear {
            highlighted = options.firstIndex { $0 == current } ?? 0
        }
    }
}

/// A row in the chooser, highlighted like a menu item.
struct ProjectChooserRow: View {
    static let height: CGFloat = 26

    let ledger: Ledger
    let choice: ProjectChoice
    let isCurrent: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack {
            ProjectChoiceLabel(ledger: ledger, choice: choice)
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

/// A search field that reports the arrow keys, Return and Escape, so a list
/// under it can follow the keyboard. It takes focus when it appears.
struct KeyboardSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FocusingSearchField {
        let field = FocusingSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.sendsSearchStringImmediately = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusingSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: KeyboardSearchField

        init(_ parent: KeyboardSearchField) {
            self.parent = parent
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            if parent.text != sender.stringValue {
                parent.text = sender.stringValue
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            searchChanged(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}

/// A search field that becomes the first responder once it's in a window.
final class FocusingSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Wait until the window has finished setting up its first responder.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
#endif

#if os(iOS)
/// A row showing the chosen project, which opens a searchable list of
/// projects. It has to be inside a navigation stack.
public struct ProjectPicker: View {
    let ledger: Ledger
    @Binding var selection: UUID?
    let title: String

    public init(ledger: Ledger, selection: Binding<UUID?>, title: String = "Project") {
        self.ledger = ledger
        _selection = selection
        self.title = title
    }

    public var body: some View {
        NavigationLink {
            ProjectChooserList(ledger: ledger, current: selection, title: title) { projectID in
                selection = projectID
            }
        } label: {
            LabeledContent(title) {
                ProjectChoiceLabel(ledger: ledger, choice: ProjectChoice(selection))
            }
        }
    }
}

/// The projects with a search field, for choosing one.
struct ProjectChooserList: View {
    let ledger: Ledger
    let current: UUID?
    let title: String
    let choose: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let options = ProjectChoice.options(in: ledger, matching: query, current: current)
        List(options) { option in
            Button {
                choose(option.projectID)
                dismiss()
            } label: {
                HStack {
                    ProjectChoiceLabel(ledger: ledger, choice: option)
                    Spacer()
                    if option.projectID == current {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if options.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Clients and projects")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

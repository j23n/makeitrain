import SwiftUI
import TrackerCore

// Small views shared by the Mac and iOS screens.

/// A project's color and title, such as "● Acme › Website".
public struct ProjectLabel: View {
    let ledger: Ledger
    let projectID: UUID?

    public init(ledger: Ledger, projectID: UUID?) {
        self.ledger = ledger
        self.projectID = projectID
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ledger.color(ofProject: projectID))
                .frame(width: 8, height: 8)
            Text(ledger.projectTitle(projectID))
                .lineLimit(1)
                .foregroundStyle(projectID == nil ? .secondary : .primary)
        }
    }
}

/// Tags as small capsules.
public struct TagList: View {
    let tags: [String]

    public init(tags: [String]) {
        self.tags = tags
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
        }
    }
}

/// A text field that edits a draft and commits it on Return or when focus
/// leaves, so typing doesn't make an undo step per keystroke. Until the
/// draft is edited, it shows the current value.
public struct CommitField: View {
    let title: String
    let value: String
    let axis: Axis
    let commit: (String) -> Void
    @State private var draft: String? = nil
    @FocusState private var focused: Bool

    public init(title: String, value: String, axis: Axis = .horizontal, commit: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.axis = axis
        self.commit = commit
    }

    public var body: some View {
        TextField(title, text: Binding(get: { draft ?? value }, set: { draft = $0 }), axis: axis)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    save()
                }
            }
            .onDisappear(perform: save)
    }

    private func save() {
        guard let text = draft else { return }
        draft = nil
        if text != value {
            commit(text)
        }
    }
}

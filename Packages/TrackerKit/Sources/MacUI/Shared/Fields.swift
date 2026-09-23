#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore

/// A text field that edits a draft and commits it on Return or when focus
/// leaves, so typing doesn't make an undo step per keystroke. Until the
/// draft is edited, it shows the current value.
struct CommitField: View {
    let title: String
    let value: String
    var axis: Axis = .horizontal
    let commit: (String) -> Void
    @State private var draft: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
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

/// Tags as tokens. Typing completes existing tags with their existing
/// spelling, and `;` is dropped. Commits when editing ends.
struct TagField: NSViewRepresentable {
    let tags: [String]
    let suggestions: [String]
    var placeholder = "Add tags"
    let commit: ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.tokenStyle = .rounded
        field.completionDelay = 0.1
        field.placeholderString = placeholder
        field.objectValue = tags
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.currentEditor() == nil, Coordinator.tokens(of: field) != tags {
            field.objectValue = tags
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: TagField

        init(_ parent: TagField) {
            self.parent = parent
        }

        static func tokens(of field: NSTokenField) -> [String] {
            (field.objectValue as? [Any])?.compactMap { $0 as? String } ?? []
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            let tokens = Tags.normalize(Self.tokens(of: field))
            if tokens != parent.tags {
                parent.commit(tokens)
            }
        }

        func tokenField(
            _ tokenField: NSTokenField,
            completionsForSubstring substring: String,
            indexOfToken tokenIndex: Int,
            indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
        ) -> [Any]? {
            let typed = substring.lowercased()
            return parent.suggestions.filter { $0.lowercased().hasPrefix(typed) }
        }

        func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
            tokens.compactMap { $0 as? String }.compactMap { token in
                Tags.normalize([token]).first.map { tag in
                    parent.suggestions.first { Tags.same($0, tag) } ?? tag
                }
            }
        }
    }
}

/// A menu that sets the project of several entries at once.
struct ProjectMenu: View {
    let ledger: Ledger
    let title: String
    let choose: (UUID?) -> Void

    var body: some View {
        Menu(title) {
            Button("No Project") {
                choose(nil)
            }
            Divider()
            ForEach(ledger.pickerProjects()) { project in
                Button(ledger.projectTitle(project.id)) {
                    choose(project.id)
                }
            }
        }
    }
}
#endif

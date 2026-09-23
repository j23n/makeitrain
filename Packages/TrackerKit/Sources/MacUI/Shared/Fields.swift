#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore

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

/// A button that opens the searchable project list in a popover and hands
/// over the project chosen, such as for several entries at once or as a
/// project to merge into.
struct ProjectChooserButton: View {
    let ledger: Ledger
    let title: String
    var offersNoProject = true
    var excluding: UUID? = nil
    let choose: (UUID?) -> Void
    @State private var choosing = false

    var body: some View {
        Button(title) {
            choosing = true
        }
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            ProjectChooser(ledger: ledger, current: nil, offersNoProject: offersNoProject, excluding: excluding) { projectID in
                choosing = false
                choose(projectID)
            } cancel: {
                choosing = false
            }
            .frame(width: 320)
        }
    }
}
#endif

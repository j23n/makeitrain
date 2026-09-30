#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// Tags as tokens. Typing completes existing tags with their existing
/// spelling, and `;` is dropped. Commits when editing ends.
struct TagField: NSViewRepresentable {
    let tags: [String]
    let suggestions: [String]
    var placeholder = "Add tags"
    /// Whether it looks like a text field. In a table cell it doesn't, and
    /// keeps to one line.
    var bordered = true
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
        if !bordered {
            field.isBezeled = false
            field.isBordered = false
            field.drawsBackground = false
            field.maximumNumberOfLines = 1
            field.cell?.wraps = false
            field.cell?.isScrollable = true
        }
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

/// A value shown as text until the pointer first comes over it, and the
/// control that edits it from then on.
///
/// Date pickers, token fields and text fields are slow to make, most of all
/// on macOS 26, where a date picker takes about 20 milliseconds. A table
/// with several of them in every row takes seconds to open, even with only
/// a few dozen rows. Made when the pointer arrives, the control is there by
/// the time it's clicked, so editing still takes one click.
struct EditOnHover<Display: View, Editor: View>: View {
    let enabled: Bool
    let display: () -> Display
    let editor: () -> Editor
    @State private var editing = false

    init(
        enabled: Bool = true,
        @ViewBuilder display: @escaping () -> Display,
        @ViewBuilder editor: @escaping () -> Editor
    ) {
        self.enabled = enabled
        self.display = display
        self.editor = editor
    }

    var body: some View {
        if editing {
            editor()
        } else {
            // As tall as the controls, so a row keeps its height when one
            // takes the text's place.
            display()
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside, enabled {
                        editing = true
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

#if DEBUG
#Preview("Tag Field") {
    Form {
        LabeledContent("Tags") {
            TagField(tags: ["design", "client-call"], suggestions: PreviewData.ledger.allTags()) { _ in }
        }
        LabeledContent("No tags") {
            TagField(tags: [], suggestions: PreviewData.ledger.allTags()) { _ in }
        }
        LabeledContent("As in a table") {
            TagField(tags: ["development"], suggestions: [], placeholder: "", bordered: false) { _ in }
        }
    }
    .formStyle(.grouped)
    .frame(width: 420)
}

#Preview("Project Chooser Button") {
    ProjectChooserButton(ledger: PreviewData.ledger, title: "Set Project…") { _ in }
        .padding(40)
}
#endif
#endif

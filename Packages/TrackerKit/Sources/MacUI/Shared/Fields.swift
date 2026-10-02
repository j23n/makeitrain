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
    /// Whether it starts editing as it shows, after the last tag, as when a
    /// table cell is clicked.
    var editsOnAppear = false
    /// Called once editing has ended and the tags are committed.
    var endEditing: (() -> Void)? = nil
    let commit: ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTokenField {
        let field = TagTokenField()
        field.editsOnAppear = editsOnAppear
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
            if let endEditing = parent.endEditing {
                // Once AppKit is done with the field, which this may remove.
                Task { @MainActor in
                    endEditing()
                }
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

/// A token field that can start editing as it shows.
private final class TagTokenField: NSTokenField {
    var editsOnAppear = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard editsOnAppear, window != nil else { return }
        editsOnAppear = false
        // Once the window has finished setting up its first responder.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, window.makeFirstResponder(self) else { return }
            // The insertion point after the last tag, rather than every tag
            // selected, so that typing adds one.
            if let editor = self.currentEditor() {
                editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
            }
        }
    }
}

/// A date and time to type over, field by field, or to pick from the
/// calendar that opens when its date is clicked, in a time zone. It has no
/// stepper. Return finishes editing, Escape puts back the date it had, and
/// the date is committed when editing ends.
struct DateTimeField: NSViewRepresentable {
    let title: String
    let date: Date
    var minimum: Date? = nil
    var maximum: Date? = nil
    let timeZone: TimeZone
    /// Whether it starts editing as it shows, as when a table cell is
    /// clicked.
    var editsOnAppear = false
    /// Called once editing has ended and the date is committed.
    var endEditing: (() -> Void)? = nil
    let commit: (Date) -> Void

    func makeNSView(context: Context) -> DateTimePicker {
        let picker = DateTimePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.presentsCalendarOverlay = true
        picker.isBezeled = true
        picker.drawsBackground = true
        picker.backgroundColor = .textBackgroundColor
        picker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        picker.setAccessibilityLabel(title)
        picker.editsOnAppear = editsOnAppear
        updateNSView(picker, context: context)
        return picker
    }

    func updateNSView(_ picker: DateTimePicker, context: Context) {
        picker.timeZone = timeZone
        picker.minDate = minimum
        picker.maxDate = maximum
        picker.isEnabled = context.environment.isEnabled
        // Not while it's edited, which would undo what's typed.
        if !picker.isEditing, picker.dateValue != date {
            picker.dateValue = date
        }
        picker.ended = { changed in
            // Once AppKit is done with the picker, which this may remove.
            Task { @MainActor in
                if let changed {
                    commit(changed)
                }
                endEditing?()
            }
        }
    }

    static func dismantleNSView(_ picker: DateTimePicker, coordinator: ()) {
        // Removed while edited, such as when its row scrolls away: what was
        // typed still counts.
        picker.finishEditing()
    }
}

/// A date picker that says when editing ends and whether the date changed,
/// and that can start editing as it shows.
///
/// Editing lasts while focus is on the picker or on the calendar it opens,
/// rather than ending whenever the picker gives up focus: AppKit shows the
/// calendar in a child window of the picker's and moves focus into it, and
/// ending editing then would take the picker away from under its calendar.
final class DateTimePicker: NSDatePicker {
    var editsOnAppear = false
    /// Called when editing ends, with the new date, or nil when it's the
    /// same as when editing began.
    var ended: ((Date?) -> Void)?
    private(set) var isEditing = false
    private var original: Date?
    /// Watches where the window's focus goes while the date is edited.
    private var focus: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard editsOnAppear, window != nil else { return }
        editsOnAppear = false
        // Once the window has finished setting up its first responder.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, !isEditing {
            isEditing = true
            original = dateValue
            watchFocus()
        }
        return became
    }

    /// Ends editing once the window's focus is on something other than this
    /// picker and its calendar.
    private func watchFocus() {
        focus = window?.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, self.isEditing else { return }
                if let responder = window.firstResponder, self.holdsFocus(responder, in: window) {
                    return
                }
                self.finishEditing()
            }
        }
    }

    /// Whether `responder` is this picker, or its calendar's window or a
    /// view in it. AppKit shows the calendar in a child window of the
    /// picker's, and while it closes, that window has the focus for a moment
    /// before the picker gets it back.
    private func holdsFocus(_ responder: NSResponder, in window: NSWindow) -> Bool {
        if responder === self {
            return true
        }
        guard let owner = (responder as? NSWindow) ?? (responder as? NSView)?.window, owner !== window else {
            return false
        }
        return owner.parent === window
    }

    /// Ends editing, unless it has ended already, and says so.
    func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        focus?.invalidate()
        focus = nil
        ended?(dateValue == original ? nil : dateValue)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            // Return or Enter.
            window?.makeFirstResponder(nil)
        case 53:
            // Escape.
            if let original {
                dateValue = original
            }
            window?.makeFirstResponder(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

/// A value shown as text until it's clicked, and then the control that
/// edits it, until editing ends. The control starts editing as it shows, and
/// calls `done` when editing ends, to show the text again.
///
/// For controls that don't look like their text, such as date fields and
/// token fields: only the one being edited looks different, whatever the
/// pointer has passed over. `EditOnHover` is for controls that do.
struct EditOnClick<Display: View, Editor: View>: View {
    let enabled: Bool
    let display: () -> Display
    let editor: (_ done: @escaping () -> Void) -> Editor
    @State private var editing = false

    init(
        enabled: Bool = true,
        @ViewBuilder display: @escaping () -> Display,
        @ViewBuilder editor: @escaping (_ done: @escaping () -> Void) -> Editor
    ) {
        self.enabled = enabled
        self.display = display
        self.editor = editor
    }

    var body: some View {
        if editing {
            editor {
                editing = false
            }
        } else {
            // As tall as the controls, so a row keeps its height when one
            // takes the text's place.
            display()
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    edit()
                }
                .accessibilityAction {
                    edit()
                }
        }
    }

    private func edit() {
        if enabled {
            editing = true
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
/// the time it's clicked, so editing still takes one click. It's for
/// controls that look like their text, such as a plain text field, since
/// the ones the pointer has passed over stay.
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

#Preview("Date Time Field") {
    VStack(alignment: .leading, spacing: 12) {
        DateTimeText(time: PreviewData.now, zone: TimeZone.current.identifier)
        DateTimeField(title: "Start", date: PreviewData.now.date, timeZone: .current) { _ in }
    }
    .padding(40)
}

#Preview("Project Chooser Button") {
    ProjectChooserButton(ledger: PreviewData.ledger, title: "Set Project…") { _ in }
        .padding(40)
}
#endif
#endif

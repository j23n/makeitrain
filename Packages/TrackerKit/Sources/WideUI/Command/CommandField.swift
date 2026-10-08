import SwiftUI
import TrackerCore
import TrackerKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The command line's text field: monospaced, with the line highlighted as
/// it's read, the project underlined in its color, tags in blue and times
/// in amber, and keys for Return, Option-Return, Tab, Up, Down and Escape,
/// on the Mac and with an iPad's or iPhone's keyboard.
public struct CommandField {
    @Binding var text: String
    var placeholder: String
    /// What the line means, for highlighting it.
    var reading: CommandReading
    var ledger: Ledger
    var fontSize: CGFloat
    /// Whether the field takes the keyboard whenever its window does, as
    /// in the menu bar's popover, or as soon as it shows, on iPhone.
    var focusesWithWindow: Bool
    /// Changing it puts the keyboard in the field, as ⌘K does.
    var focusRequest: Int
    /// Changing it puts the insertion point at `cursor`, a UTF-16 offset,
    /// as after taking a suggestion.
    var cursorRequest: Int
    var cursor: Int?
    var onSubmit: (_ alternate: Bool) -> Void
    var onTab: () -> Bool
    var onUp: () -> Bool
    var onDown: () -> Bool
    var onCancel: () -> Void
    /// Where the insertion point is, as a UTF-16 offset, when it moves.
    var onCursorChange: (Int) -> Void
    var onFocusChange: (Bool) -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        reading: CommandReading,
        ledger: Ledger,
        fontSize: CGFloat = 15.5,
        focusesWithWindow: Bool = false,
        focusRequest: Int = 0,
        cursorRequest: Int = 0,
        cursor: Int? = nil,
        onSubmit: @escaping (_ alternate: Bool) -> Void,
        onTab: @escaping () -> Bool = { false },
        onUp: @escaping () -> Bool = { false },
        onDown: @escaping () -> Bool = { false },
        onCancel: @escaping () -> Void = {},
        onCursorChange: @escaping (Int) -> Void = { _ in },
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _text = text
        self.placeholder = placeholder
        self.reading = reading
        self.ledger = ledger
        self.fontSize = fontSize
        self.focusesWithWindow = focusesWithWindow
        self.focusRequest = focusRequest
        self.cursorRequest = cursorRequest
        self.cursor = cursor
        self.onSubmit = onSubmit
        self.onTab = onTab
        self.onUp = onUp
        self.onDown = onDown
        self.onCancel = onCancel
        self.onCursorChange = onCursorChange
        self.onFocusChange = onFocusChange
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: PlatformColor(Theme.text),
        ]
    }

    var placeholderAttributes: [NSAttributedString.Key: Any] {
        [
            .font: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: PlatformColor(Theme.text3),
        ]
    }

    /// Colors the words of the line by what they mean.
    func highlight(_ reading: CommandReading, in string: NSMutableAttributedString) {
        for token in reading.tokens {
            let range = NSRange(token.range, in: reading.text)
            guard range.location != NSNotFound, NSMaxRange(range) <= string.length else { continue }
            switch token.kind {
            case let .project(id):
                string.addAttributes([
                    .underlineStyle: NSUnderlineStyle.thick.rawValue,
                    .underlineColor: PlatformColor(ledger.tint(ofProject: id).ink),
                ], range: range)
            case .client:
                string.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: PlatformColor(Theme.text2),
                ], range: range)
            case .tag:
                string.addAttribute(.foregroundColor, value: PlatformColor(Theme.tag), range: range)
            case .time:
                string.addAttributes([
                    .foregroundColor: PlatformColor(Theme.amberText),
                    .backgroundColor: PlatformColor(Theme.amberFill),
                ], range: range)
            case .keyword:
                string.addAttribute(.foregroundColor, value: PlatformColor(Theme.accent), range: range)
            case .name:
                string.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold), range: range)
            case let .color(hex):
                string.addAttribute(.foregroundColor, value: PlatformColor(ProjectTint(hex: hex).ink), range: range)
            case .unknown:
                string.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: PlatformColor(Theme.amber),
                ], range: range)
            case .note:
                break
            }
        }
    }
}

#if os(macOS)
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont

extension CommandField: NSViewRepresentable {
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.textColor = NSColor(Theme.text)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.focusesWithWindow = focusesWithWindow
        field.onFocusChange = { focused in context.coordinator.parent.onFocusChange(focused) }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: placeholderAttributes)
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.lastCursorRequest = cursorRequest
        context.coordinator.watchSelection(of: field)
        return field
    }

    public func updateNSView(_ field: CommandTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Moves of the insertion point from here on follow the line's
        // state, so they aren't reported back.
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: placeholderAttributes)
        coordinator.highlight(field)
        if coordinator.lastCursorRequest != cursorRequest {
            coordinator.lastCursorRequest = cursorRequest
            if let cursor, let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: min(cursor, (field.stringValue as NSString).length), length: 0)
            }
        }
        if coordinator.lastFocusRequest != focusRequest {
            coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeKeyAndOrderFront(nil)
                // A field being edited keeps its insertion point, rather
                // than having its line selected again.
                if field.currentEditor() == nil {
                    field.window?.makeFirstResponder(field)
                }
            }
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandField
        var lastFocusRequest = 0
        var lastCursorRequest = 0
        /// Whether the field is being changed to match the line, rather
        /// than by the person typing.
        var isUpdating = false
        private weak var field: NSTextField?
        private var selectionObserver: NSObjectProtocol?

        init(_ parent: CommandField) {
            self.parent = parent
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        /// Reports the insertion point whenever it moves in the field. The
        /// window's fields share one field editor, so a move counts only
        /// while the editor is this field's.
        func watchSelection(of field: NSTextField) {
            self.field = field
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let editor = notification.object as? NSText, editor === self.field?.currentEditor() else { return }
                    self.reportCursor(editor)
                }
            }
        }

        /// The end of the selection, where typing goes on.
        func reportCursor(_ editor: NSText) {
            guard !isUpdating else { return }
            parent.onCursorChange(NSMaxRange(editor.selectedRange))
        }

        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            if let editor = field.currentEditor() {
                reportCursor(editor)
            }
        }

        public func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            highlight(field)
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(NSApp.currentEvent?.modifierFlags.contains(.option) == true)
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(true)
                return true
            case #selector(NSResponder.insertTab(_:)):
                return parent.onTab()
            case #selector(NSResponder.moveUp(_:)):
                return parent.onUp()
            case #selector(NSResponder.moveDown(_:)):
                return parent.onDown()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        /// Colors the line by what it means.
        func highlight(_ field: NSTextField) {
            let text = field.stringValue
            let reading = parent.reading
            guard reading.text == text else { return }
            guard let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage else {
                let attributed = NSMutableAttributedString(string: text, attributes: parent.baseAttributes)
                parent.highlight(reading, in: attributed)
                field.attributedStringValue = attributed
                return
            }
            guard storage.string == text else { return }
            storage.beginEditing()
            storage.setAttributes(parent.baseAttributes, range: NSRange(location: 0, length: storage.length))
            parent.highlight(reading, in: storage)
            storage.endEditing()
            editor.typingAttributes = parent.baseAttributes
            editor.insertionPointColor = NSColor(Theme.text)
        }
    }
}

/// A text field that can take the keyboard whenever its window becomes
/// key, and says when it gains or loses the keyboard.
public final class CommandTextField: NSTextField {
    var focusesWithWindow = false
    var onFocusChange: (Bool) -> Void = { _ in }
    private var observer: NSObjectProtocol?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        guard let window, focusesWithWindow else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentEditor() == nil else { return }
                self.window?.makeFirstResponder(self)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isKeyWindow == true else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocusChange(true)
        }
        return became
    }

    public override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange(false)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
#else
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont

extension CommandField: UIViewRepresentable {
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.textColor = UIColor(Theme.text)
        field.tintColor = UIColor(Theme.accent)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.keyboardType = .asciiCapable
        field.returnKeyType = .go
        field.delegate = context.coordinator
        field.keys = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = text
        if focusesWithWindow {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
        return field
    }

    public func updateUIView(_ field: CommandTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Moves of the caret from here on follow the line's state, so they
        // aren't reported back.
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        if field.text != text {
            field.text = text
        }
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: placeholderAttributes)
        coordinator.highlight(field)
        if coordinator.cursorRequest != cursorRequest {
            coordinator.cursorRequest = cursorRequest
            if let cursor, let position = field.position(from: field.beginningOfDocument, offset: min(cursor, (field.text ?? "").utf16.count)) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
        }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    public final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CommandField
        var focusRequest: Int
        var cursorRequest: Int
        /// Whether the field is being changed to match the line, rather
        /// than by the person typing.
        var isUpdating = false

        init(_ parent: CommandField) {
            self.parent = parent
            focusRequest = parent.focusRequest
            cursorRequest = parent.cursorRequest
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
            reportCursor(field)
        }

        public func textFieldDidChangeSelection(_ field: UITextField) {
            reportCursor(field)
        }

        /// The end of the selection, where typing goes on.
        private func reportCursor(_ field: UITextField) {
            guard !isUpdating, let range = field.selectedTextRange else { return }
            parent.onCursorChange(field.offset(from: field.beginningOfDocument, to: range.end))
        }

        public func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit(false)
            return false
        }

        public func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onFocusChange(true)
        }

        public func textFieldDidEndEditing(_ field: UITextField) {
            parent.onFocusChange(false)
        }

        /// Colors the line by what it means, keeping the caret where it
        /// is. Text that's still being composed, as with a Japanese
        /// keyboard, is left alone.
        func highlight(_ field: UITextField) {
            let reading = parent.reading
            guard field.markedTextRange == nil, let text = field.text, reading.text == text else { return }
            let attributed = NSMutableAttributedString(string: text, attributes: parent.baseAttributes)
            parent.highlight(reading, in: attributed)
            if let current = field.attributedText, current.isEqual(to: attributed) {
                return
            }
            let selection = field.selectedTextRange
            field.attributedText = attributed
            field.selectedTextRange = selection
            field.typingAttributes = parent.baseAttributes
        }
    }
}

/// The text field, taking Tab, the arrows, Escape and Option-Return from a
/// keyboard as the Mac's does.
public final class CommandTextField: UITextField {
    weak var keys: CommandField.Coordinator?

    public override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tab)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(up)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(down)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
            UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(alternateReturn)),
        ]
        for command in commands {
            command.wantsPriorityOverSystemBehavior = true
        }
        return commands
    }

    @objc private func tab() {
        _ = keys?.parent.onTab()
    }

    @objc private func up() {
        _ = keys?.parent.onUp()
    }

    @objc private func down() {
        _ = keys?.parent.onDown()
    }

    @objc private func escape() {
        keys?.parent.onCancel()
    }

    @objc private func alternateReturn() {
        keys?.parent.onSubmit(true)
    }
}
#endif

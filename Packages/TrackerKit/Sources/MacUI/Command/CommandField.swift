#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The command line's text field: monospaced, with the line highlighted as
/// it's read, the project underlined in its color, tags in blue and times
/// in amber, and keys for Return, Option-Return, Tab, Up, Down and Escape.
struct CommandField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// What the line means, for highlighting it.
    var reading: CommandReading
    var ledger: Ledger
    var fontSize: CGFloat = 15.5
    /// Whether the field takes the keyboard whenever its window does, as
    /// in the menu bar's popover.
    var focusesWithWindow = false
    /// Changing it puts the keyboard in the field, as ⌘K does.
    var focusRequest = 0
    var onSubmit: (_ alternate: Bool) -> Void
    var onTab: () -> Bool = { false }
    var onUp: () -> Bool = { false }
    var onDown: () -> Bool = { false }
    var onCancel: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CommandTextField {
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
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(Theme.text3),
        ])
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.lastFocusRequest = focusRequest
        return field
    }

    func updateNSView(_ field: CommandTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        context.coordinator.highlight(field)
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeKeyAndOrderFront(nil)
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandField
        var lastFocusRequest = 0

        init(_ parent: CommandField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            highlight(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
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

        private var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                .foregroundColor: NSColor(Theme.text),
            ]
        }

        /// Colors the line by what it means.
        func highlight(_ field: NSTextField) {
            let text = field.stringValue
            let reading = parent.reading
            guard reading.text == text else { return }
            guard let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage else {
                let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
                apply(reading, to: attributed)
                field.attributedStringValue = attributed
                return
            }
            guard storage.string == text else { return }
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
            apply(reading, to: storage)
            storage.endEditing()
            editor.typingAttributes = baseAttributes
            editor.insertionPointColor = NSColor(Theme.text)
        }

        private func apply(_ reading: CommandReading, to string: NSMutableAttributedString) {
            for token in reading.tokens {
                let range = NSRange(token.range, in: reading.text)
                guard range.location != NSNotFound, NSMaxRange(range) <= string.length else { continue }
                switch token.kind {
                case let .project(id):
                    string.addAttributes([
                        .underlineStyle: NSUnderlineStyle.thick.rawValue,
                        .underlineColor: NSColor(parent.ledger.tint(ofProject: id).ink),
                    ], range: range)
                case .client:
                    string.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor(Theme.text2),
                    ], range: range)
                case .tag:
                    string.addAttribute(.foregroundColor, value: NSColor(Theme.tag), range: range)
                case .time:
                    string.addAttributes([
                        .foregroundColor: NSColor(Theme.amberText),
                        .backgroundColor: NSColor(Theme.amberFill),
                    ], range: range)
                case .keyword:
                    string.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: range)
                case .name:
                    string.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold), range: range)
                case let .color(hex):
                    string.addAttribute(.foregroundColor, value: NSColor(ProjectTint(hex: hex).ink), range: range)
                case .unknown:
                    string.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                        .underlineColor: NSColor(Theme.amber),
                    ], range: range)
                case .note:
                    break
                }
            }
        }
    }
}

/// A text field that can take the keyboard whenever its window becomes
/// key, and says when it gains or loses the keyboard.
final class CommandTextField: NSTextField {
    var focusesWithWindow = false
    var onFocusChange: (Bool) -> Void = { _ in }
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocusChange(true)
        }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange(false)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
#endif

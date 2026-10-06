#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// The command line's field on iPhone: SF Mono, with what the line means
/// colored as it's typed, as on the Mac: a project underlined in its
/// color, tags in blue, times in amber, and a name that matches nothing
/// dotted underneath.
struct PhoneCommandField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// What the line means, for coloring it.
    var reading: CommandReading
    var ledger: Ledger
    var fontSize: CGFloat = 17
    /// Changing it puts the keyboard in the field.
    var focusRequest = 0
    var onSubmit: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
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
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = text
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: UIColor(Theme.text3),
        ])
        context.coordinator.highlight(field)
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PhoneCommandField
        var focusRequest = 0

        init(_ parent: PhoneCommandField) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.onFocusChange(false)
        }

        private var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                .foregroundColor: UIColor(Theme.text),
            ]
        }

        /// Colors the line by what it means, keeping the caret where it is.
        /// Text that's still being composed, as with a Japanese keyboard,
        /// is left alone.
        func highlight(_ field: UITextField) {
            let reading = parent.reading
            guard field.markedTextRange == nil, let text = field.text, reading.text == text else { return }
            let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
            apply(reading, to: attributed)
            if let current = field.attributedText, current.isEqual(to: attributed) {
                return
            }
            let selection = field.selectedTextRange
            field.attributedText = attributed
            field.selectedTextRange = selection
            field.typingAttributes = baseAttributes
        }

        private func apply(_ reading: CommandReading, to string: NSMutableAttributedString) {
            for token in reading.tokens {
                let range = NSRange(token.range, in: reading.text)
                guard range.location != NSNotFound, NSMaxRange(range) <= string.length else { continue }
                switch token.kind {
                case let .project(id):
                    string.addAttributes([
                        .underlineStyle: NSUnderlineStyle.thick.rawValue,
                        .underlineColor: UIColor(parent.ledger.tint(ofProject: id).ink),
                    ], range: range)
                case .client:
                    string.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: UIColor(Theme.text2),
                    ], range: range)
                case .tag:
                    string.addAttribute(.foregroundColor, value: UIColor(Theme.tag), range: range)
                case .time:
                    string.addAttributes([
                        .foregroundColor: UIColor(Theme.amberText),
                        .backgroundColor: UIColor(Theme.amberFill),
                    ], range: range)
                case .keyword:
                    string.addAttribute(.foregroundColor, value: UIColor(Theme.accent), range: range)
                case .name:
                    string.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold), range: range)
                case let .color(hex):
                    string.addAttribute(.foregroundColor, value: UIColor(ProjectTint(hex: hex).ink), range: range)
                case .unknown:
                    string.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                        .underlineColor: UIColor(Theme.amber),
                    ], range: range)
                case .note:
                    break
                }
            }
        }
    }
}
#endif

import SwiftUI
import TrackerCore

// Small pieces the redesigned screens share on the Mac, iPhone and iPad.

/// A key, as in "⏎ accept" or "⌘K": outlined, filled for the key that
/// does what's suggested, or outlined in the inverse colors on a button
/// that's filled.
public struct KeyCap: View {
    let key: String
    let inverted: Bool
    let onInverse: Bool

    public init(_ key: String, inverted: Bool = false, onInverse: Bool = false) {
        self.key = key
        self.inverted = inverted
        self.onInverse = onInverse
    }

    public var body: some View {
        Text(key)
            .font(.system(size: 11, weight: inverted ? .semibold : .regular))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .foregroundStyle(inverted || onInverse ? Theme.inverseText : Theme.text2)
            .background {
                if inverted {
                    RoundedRectangle(cornerRadius: 5).fill(Theme.inverse)
                } else {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(onInverse ? Theme.inverseText.opacity(0.3) : Theme.key)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A key and what it does, as under the command line.
public struct KeyHint: View {
    let key: String
    let text: String

    public init(_ key: String, _ text: String) {
        self.key = key
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .foregroundStyle(Theme.text2)
            Text(text)
                .foregroundStyle(Theme.text3)
        }
        .font(.system(size: 11.5))
        .accessibilityElement(children: .combine)
    }
}

/// A project's color as a dot, or a ring for no project.
public struct TintDot: View {
    let tint: ProjectTint?
    let size: CGFloat

    public init(_ tint: ProjectTint?, size: CGFloat = 8) {
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Group {
            if let tint {
                Circle().fill(tint.ink)
            } else {
                Circle().strokeBorder(Theme.text3, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A project's dot and name, such as "● Website", or "Unassigned".
public struct ProjectName: View {
    let ledger: Ledger
    let projectID: UUID?
    let showsClient: Bool
    let weight: Font.Weight

    public init(ledger: Ledger, projectID: UUID?, showsClient: Bool = false, weight: Font.Weight = .regular) {
        self.ledger = ledger
        self.projectID = projectID
        self.showsClient = showsClient
        self.weight = weight
    }

    public var body: some View {
        HStack(spacing: 6) {
            TintDot(projectID == nil ? nil : ledger.tint(ofProject: projectID))
            Text(title)
                .fontWeight(weight)
                .lineLimit(1)
                .foregroundStyle(projectID == nil ? Theme.text2 : Theme.text)
        }
    }

    private var title: String {
        guard let projectID else { return "Unassigned" }
        return showsClient ? ledger.projectTitle(projectID) : ledger.projects[projectID]?.name ?? "Unknown project"
    }
}

/// The numbered marker of a correction, on the week and in the list.
public struct CorrectionMarker: View {
    let number: Int

    public init(_ number: Int) {
        self.number = number
    }

    public var body: some View {
        Text("\(number)")
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.markerText)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Theme.marker))
            .accessibilityLabel(Text("Correction \(number)"))
    }
}

/// A time that changes: the old value struck through and the new one in
/// amber, or just the value when it stays.
public struct ChangedText: View {
    let old: String?
    let new: String
    let size: CGFloat

    public init(old: String?, new: String, size: CGFloat = 12) {
        self.old = old
        self.new = new
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let old, old != new {
                Text(old)
                    .strikethrough(true, color: Theme.amber)
                    .foregroundStyle(Theme.text3)
                Text(new)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.amberText)
            } else {
                Text(new)
            }
        }
        .font(.system(size: size))
        .monospacedDigit()
    }
}

/// A button that's one of the choices for a correction or command: the
/// suggested one inverted with its key, the others outlined.
public struct ChoiceButtonStyle: ButtonStyle {
    let suggested: Bool
    let compact: Bool

    public init(suggested: Bool = false, compact: Bool = false) {
        self.suggested = suggested
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, suggested: suggested, compact: compact)
    }

    private struct Styled: View {
        let configuration: Configuration
        let suggested: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12.5 : 13, weight: suggested ? .semibold : .medium))
                .foregroundStyle(suggested ? Theme.inverseText : (isEnabled ? Theme.text : Theme.text3))
                .padding(.horizontal, compact ? 10 : 12)
                .frame(minHeight: compact ? 28 : 32)
                .background {
                    if suggested {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.inverse)
                    } else {
                        RoundedRectangle(cornerRadius: compact ? 7 : 8).strokeBorder(isEnabled ? Theme.strongLine : Theme.line)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

/// A segmented control in the redesign's look: a row of labels on a
/// fill, the chosen one raised.
public struct SegmentPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    public init(_ options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let chosen = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? Theme.text : Theme.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if chosen {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.segment)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill))
    }
}

/// Diagonal stripes, drawn over time that's counted twice.
public struct Hatching: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 6
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Theme.hatch), lineWidth: 1.5)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

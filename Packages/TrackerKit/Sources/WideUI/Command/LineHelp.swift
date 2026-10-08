import SwiftUI
import TrackerKit

/// Something to add to a line, as a button's label: outlined, with a
/// project's color, and highlighted with ⇥ when Tab takes it.
public struct ChipLabel: View {
    /// How big it is: `.touch` for a finger, as on iPhone, where there's
    /// no Tab to highlight what it takes, nor a sidebar to fit.
    public enum Size {
        case regular
        case touch
    }

    let chip: LineChip
    let size: Size

    public init(_ chip: LineChip, size: Size = .regular) {
        self.chip = chip
        self.size = size
    }

    private var isHighlighted: Bool {
        chip.isHighlighted && size == .regular
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let tint = chip.tint {
                TintDot(tint, size: 7)
            }
            Text(chip.title)
                .lineLimit(1)
                .truncationMode(.tail)
            if isHighlighted {
                KeyCap("⇥")
            }
        }
        .font(.system(size: size == .touch ? 13 : 12.5))
        .foregroundStyle(chip.isTag ? Theme.tag : Theme.text)
        .padding(.horizontal, size == .touch ? 13 : 10)
        .frame(height: size == .touch ? 36 : 28)
        .background(Capsule().fill(isHighlighted ? Theme.accentFill : Color.clear))
        .overlay(Capsule().strokeBorder(isHighlighted ? Theme.accentLine : Theme.strongLine))
        .contentShape(Capsule())
        .frame(maxWidth: size == .touch ? nil : Sidebar.width - 48, alignment: .leading)
    }
}

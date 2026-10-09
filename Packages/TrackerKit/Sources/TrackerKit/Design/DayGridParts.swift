import SwiftUI
import TrackerCore

// Pieces the wide week's day columns and the iPhone's day grid draw alike,
// each at its own size.

/// An entry's times as a suggestion would change them, such as
/// "09:00–12:40 11:00": each time that changes struck through, with the
/// new one beside it. Its parts go in the row it's put in.
public struct ChangedSpan: View {
    let before: TimeEntry
    let after: TimeEntry
    let zone: String
    let size: CGFloat

    public init(before: TimeEntry, after: TimeEntry, zone: String, size: CGFloat) {
        self.before = before
        self.after = after
        self.zone = zone
        self.size = size
    }

    public var body: some View {
        ChangedText(old: before.start != after.start ? Format.time(before.start, zone: zone) : nil, new: Format.time(after.start, zone: zone), size: size)
        Text("–")
        ChangedText(
            old: before.end != after.end ? before.end.map { Format.time($0, zone: zone) } ?? "now" : nil,
            new: after.end.map { Format.time($0, zone: zone) } ?? "now",
            size: size
        )
    }
}

extension View {
    /// An entry's block in `shape`, filled in its project's tint, more
    /// strongly while it's selected or running, and outlined to show it's
    /// selected, or else that a suggestion would change it, or else that it
    /// has no project, or else in its tint.
    public func entryBlockChrome<S: InsettableShape>(
        _ shape: S,
        tint: ProjectTint,
        unassigned: Bool,
        selected: Bool,
        running: Bool,
        changed: Bool
    ) -> some View {
        modifier(EntryBlockChrome(shape: shape, tint: tint, unassigned: unassigned, selected: selected, running: running, changed: changed))
    }

    /// An entry a suggestion would add, outlined in dashes: grey on nothing
    /// for a calendar event, amber on its project's tint for the part of a
    /// split entry.
    public func suggestedAdditionChrome(isEvent: Bool, tint: ProjectTint, cornerRadius: CGFloat) -> some View {
        background {
            if !isEvent {
                RoundedRectangle(cornerRadius: cornerRadius).fill(tint.fill)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isEvent ? Theme.ghost : Theme.amber, style: StrokeStyle(lineWidth: isEvent ? 1 : 1.5, dash: [4, 3]))
        )
        .clipped()
    }
}

private struct EntryBlockChrome<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: ProjectTint
    let unassigned: Bool
    let selected: Bool
    let running: Bool
    let changed: Bool

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(border)
            .clipShape(shape)
            .contentShape(shape)
    }

    private var fill: Color {
        if unassigned { return Theme.fill }
        return selected || running ? tint.strongFill : tint.fill
    }

    @ViewBuilder
    private var border: some View {
        if selected {
            shape.strokeBorder(Theme.selection, lineWidth: 2)
        } else if changed {
            shape.strokeBorder(Theme.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        } else if unassigned {
            shape.strokeBorder(Theme.ghost, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(tint.ink, lineWidth: 1)
        }
    }
}

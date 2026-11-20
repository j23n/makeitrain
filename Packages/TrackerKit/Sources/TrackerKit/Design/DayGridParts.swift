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
    /// strongly while it's selected or running, and edged to show that a
    /// suggestion would change it, or else that it overlaps another entry,
    /// or else that it has no project, or else in its tint. A selected
    /// block is outlined around that edge, so the edge still shows.
    public func entryBlockChrome<S: InsettableShape>(
        _ shape: S,
        tint: ProjectTint,
        unassigned: Bool,
        selected: Bool,
        running: Bool,
        changed: Bool,
        overlaps: Bool = false
    ) -> some View {
        modifier(EntryBlockChrome(shape: shape, tint: tint, unassigned: unassigned, selected: selected, running: running, changed: changed, overlaps: overlaps))
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
    let overlaps: Bool

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(border)
            .clipShape(shape)
            .overlay {
                if selected {
                    shape.inset(by: -2).strokeBorder(Theme.selection, lineWidth: 2)
                }
            }
            .contentShape(shape)
    }

    private var fill: Color {
        if unassigned { return Theme.fill }
        return selected || running ? tint.strongFill : tint.fill
    }

    @ViewBuilder
    private var border: some View {
        if changed {
            shape.strokeBorder(Theme.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        } else if overlaps {
            shape.strokeBorder(Theme.amber, lineWidth: 1.5)
        } else if unassigned {
            shape.strokeBorder(Theme.ghost, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(tint.ink, lineWidth: 1)
        }
    }
}

/// A new entry being drawn on a grid, before it's saved: a dashed outline
/// in the accent color, with its times and length, and "New entry".
public struct NewEntryOutline: View {
    let startSecond: Int
    let endSecond: Int
    let height: CGFloat
    let size: CGFloat

    public init(startSecond: Int, endSecond: Int, height: CGFloat, size: CGFloat = 10.5) {
        self.startSecond = startSecond
        self.endSecond = endSecond
        self.height = height
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Format.time(secondOfDay: startSecond))–\(Format.time(secondOfDay: endSecond)) · \(Format.duration(Int64(endSecond - startSecond) * 1000))")
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            if height >= 34 {
                Text("New entry")
                    .font(.system(size: size + 1))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, height < 22 ? 0 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height < 22 ? .leading : .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentFill))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}

/// A round handle on a new entry's top or bottom, to drag its start or
/// end. It can be grabbed a little around the dot, 28 points across, or
/// 44 with `touch`.
public struct NewEntryHandle: View {
    let touch: Bool

    public init(touch: Bool = false) {
        self.touch = touch
    }

    public var body: some View {
        Circle()
            .fill(Theme.canvas)
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
            .frame(width: touch ? 14 : 12, height: touch ? 14 : 12)
            .frame(width: touch ? 44 : 28, height: touch ? 44 : 28)
            .contentShape(Rectangle())
    }
}

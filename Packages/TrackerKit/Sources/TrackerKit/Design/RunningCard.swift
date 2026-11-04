import SwiftUI
import TrackerCore

// The running timer and today's time, as the command lines show them on
// the Mac, iPhone and iPad.

/// The running timer over a command line: a bar in its project's color,
/// the project and its client, the tags and note and when it started, how
/// long it's run, and Stop.
public struct RunningCard: View {
    let model: AppModel
    let running: ResolvedEntry
    /// Bigger, for a finger, as on iPhone.
    let touch: Bool

    public init(model: AppModel, running: ResolvedEntry, touch: Bool = false) {
        self.model = model
        self.running = running
        self.touch = touch
    }

    public var body: some View {
        let entry = running.entry
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.projectID == nil ? Theme.text3 : model.ledger.tint(ofProject: entry.projectID).ink)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(projectName)
                        .font(.system(size: touch ? 16 : 14, weight: .semibold))
                        .foregroundStyle(entry.projectID == nil ? Theme.text2 : Theme.text)
                    if let client = model.ledger.client(forProject: entry.projectID) {
                        Text(client.name)
                            .font(.system(size: touch ? 13 : 12))
                            .foregroundStyle(Theme.text3)
                    }
                }
                .lineLimit(1)
                detail
                    .font(.system(size: touch ? 13 : 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(Format.duration(model.duration(of: running)))
                .font(.system(size: touch ? 24 : 22, weight: .semibold))
                .monospacedDigit()
            StopTimerButton(model: model, size: touch ? 44 : 32)
        }
        .padding(.leading, touch ? 16 : 14)
        .padding(.trailing, touch ? 10 : 12)
        .padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Running: \(model.ledger.projectTitle(entry.projectID)), \(Format.duration(model.duration(of: running)))"))
    }

    private var projectName: String {
        running.entry.projectID.flatMap { model.ledger.projects[$0]?.name } ?? "Unassigned"
    }

    /// The tags, the note and when it started, such as "#12 Fix login ·
    /// since 9:30".
    private var detail: Text {
        let entry = running.entry
        var text = Text(verbatim: "")
        for tag in entry.tags {
            text = text + Text(verbatim: Tags.typed(tag) + " ").foregroundColor(Theme.tag)
        }
        if !entry.note.isEmpty {
            text = text + Text(verbatim: entry.note + " ").foregroundColor(Theme.text2)
        }
        let since = "since \(Format.time(running.start, zone: entry.timeZone))"
        let separator = entry.tags.isEmpty && entry.note.isEmpty ? "" : "· "
        return text + Text(verbatim: separator + since).foregroundColor(Theme.text3)
    }
}

/// Stops the running timer: a square on a filled key, with ⌘. as its
/// shortcut where `shortcut` is set.
public struct StopTimerButton: View {
    let model: AppModel
    let size: CGFloat
    let shortcut: Bool
    @Environment(\.undoManager) private var undoManager

    public init(model: AppModel, size: CGFloat, shortcut: Bool = true) {
        self.model = model
        self.size = size
        self.shortcut = shortcut
    }

    public var body: some View {
        let button = Button {
            model.stopTimer(undoManager: undoManager)
        } label: {
            RoundedRectangle(cornerRadius: max(1.5, size * 0.07))
                .fill(Theme.inverseText)
                .frame(width: (size * 0.3).rounded(), height: (size * 0.3).rounded())
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.28).fill(Theme.inverse))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isReadOnly)
        .help("Stop the timer (⌘.)")
        .accessibilityLabel(Text("Stop the timer"))
        if shortcut {
            button.keyboardShortcut(".", modifiers: .command)
        } else {
            button
        }
    }
}

/// Today's time, and a bar of it by project against an eight-hour day.
public struct TodayTotal: View {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    /// How long the bar is.
    private static let width: CGFloat = 96
    /// The day the bar is measured against, unless today had more.
    private static let day: Int64 = 8 * 3_600_000

    public var body: some View {
        let byProject = model.dayTotals.projects(on: model.today, now: model.now)
        let total = byProject.values.reduce(0, +)
        let parts = byProject.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let scale = CGFloat(max(total, Self.day))
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Today")
                    .foregroundStyle(Theme.text2)
                Text(Format.duration(total))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.key == nil ? Theme.text3 : model.ledger.tint(ofProject: part.key).bar)
                        .frame(width: max(2, Self.width * CGFloat(part.value) / scale))
                }
            }
            .frame(width: Self.width, height: 6, alignment: .leading)
            .background(Theme.emptyBar)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Running Card") {
    let model = PreviewData.model()
    return VStack(spacing: 0) {
        if let running = model.running {
            RunningCard(model: model, running: running)
            Divider()
            RunningCard(model: model, running: running, touch: true)
        }
        Divider()
        TodayTotal(model: model)
            .padding(14)
    }
    .frame(width: 390)
    .background(Theme.popover)
}
#endif

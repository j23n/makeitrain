#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// Where the main window's detail column is, for centering the timer over
/// it. It's kept apart from the window's own state so that resizing the
/// window or the sidebar redraws only the timer.
@Observable
final class DetailColumn {
    /// In window coordinates.
    var frame: CGRect = .zero
}

/// The timer in the main window's toolbar.
///
/// The toolbar centers its principal item in the window, which puts it off
/// to the left of the detail column while the sidebar shows. Padding on its
/// leading side moves it to the middle of the column instead, as far as that
/// leaves room for the title.
struct ToolbarTimer: View {
    let model: AppModel
    let detail: DetailColumn
    @State private var width: CGFloat = 0

    var body: some View {
        TimerCapsule(model: model)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
            .padding(.leading, Self.leadingPadding(detail: detail.frame, width: width, titleSpace: Self.titleSpace))
    }

    /// The padding that moves an item `width` wide, centered in a window that
    /// ends where `detail` does, over the middle of `detail`, as far as the
    /// item stays `titleSpace` clear of the column's leading edge.
    ///
    /// Padding moves the item's content right by half the padding, and makes
    /// the item reach as far to the left as it does to the right.
    static func leadingPadding(detail: CGRect, width: CGFloat, titleSpace: CGFloat) -> CGFloat {
        guard detail.minX > 0, width > 0 else { return 0 }
        let room = detail.maxX - 2 * (detail.minX + titleSpace) - width
        return max(0, min(detail.minX, room)).rounded()
    }

    /// Room for the longest screen title, with the space around it. The same
    /// for every screen, so the timer doesn't move when the screen changes.
    static let titleSpace: CGFloat = {
        let font = NSFont.boldSystemFont(ofSize: 15)
        let widest = Screen.allCases
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ceil(widest) + 40
    }()
}

/// A capsule with a round button to start a timer, or with the running
/// timer and a round button to stop it, and a menu of recent projects and
/// tags to start or switch to.
struct TimerCapsule: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let recents = model.ledger.recentCombinations()
        HStack(spacing: 0) {
            if let running = model.running {
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    TimerGlyph(title: "Stop Timer", systemImage: "stop.fill", color: .red)
                }
                .buttonStyle(TimerButtonStyle())
                .help("Stop the timer")
                RunningTimerSummary(model: model, running: running)
                    .padding(.leading, 8)
            } else {
                Button {
                    model.startTimer(undoManager: undoManager)
                } label: {
                    HStack(spacing: 8) {
                        TimerGlyph(title: "Start Timer", systemImage: "play.fill", color: .accentColor)
                        Text("Start Timer")
                            .fontWeight(.medium)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(TimerButtonStyle())
                .help("Start a timer without a project")
            }
            if !recents.isEmpty {
                Divider()
                    .frame(height: 16)
                    .padding(.leading, 10)
                recentsMenu(recents)
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, recents.isEmpty ? 12 : 4)
        .frame(height: 28)
        .timerCapsule(tint: model.running.map { model.ledger.color(ofProject: $0.entry.projectID) })
        .disabled(model.isReadOnly)
    }

    private func recentsMenu(_ recents: [Combination]) -> some View {
        Menu {
            Section(model.running == nil ? "Start" : "Switch To") {
                ForEach(recents, id: \.self) { combination in
                    Button(title(of: combination)) {
                        model.startTimer(combination, undoManager: undoManager)
                    }
                    .disabled(model.running.map { combination.matches($0.entry) } ?? false)
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.running == nil ? "Start a timer with a recent project and tags" : "Switch to a recent project and tags")
    }

    private func title(of combination: Combination) -> String {
        let project = model.ledger.projectTitle(combination.projectID)
        return combination.tags.isEmpty ? project : "\(project) · \(combination.tags.joined(separator: ", "))"
    }
}

/// The running timer's project, note or tags, and time so far.
private struct RunningTimerSummary: View {
    let model: AppModel
    let running: ResolvedEntry

    var body: some View {
        let entry = running.entry
        HStack(spacing: 6) {
            Circle()
                .fill(model.ledger.color(ofProject: entry.projectID))
                .frame(width: 8, height: 8)
            Text(model.ledger.projectTitle(entry.projectID))
                .fontWeight(.medium)
                .foregroundStyle(entry.projectID == nil ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            Text(Format.duration(model.duration(of: running)))
                .fontWeight(.semibold)
                .monospacedDigit()
                .padding(.leading, 4)
        }
        .help(tooltip)
    }

    /// The note, or the tags if there's no note.
    private var subtitle: String {
        running.entry.note.isEmpty ? running.entry.tags.joined(separator: ", ") : running.entry.note
    }

    private var tooltip: String {
        var lines = ["Started \(Format.time(running.start, zone: running.entry.timeZone))"]
        if !running.entry.note.isEmpty, !running.entry.tags.isEmpty {
            lines.append(running.entry.tags.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// A white symbol on a colored circle, the timer's start or stop button.
private struct TimerGlyph: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            // The play triangle's weight sits left of its middle.
            .offset(x: systemImage == "play.fill" ? 1 : 0)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
    }
}

/// Plain, dimmed while pressed.
private struct TimerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// A capsule behind the timer: glass from macOS 26, before that a fill,
    /// tinted with the running timer's project color.
    @ViewBuilder
    func timerCapsule(tint: Color?) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(tint.map { Glass.regular.tint($0.opacity(0.3)) } ?? .regular, in: .capsule)
        } else {
            filledTimerCapsule(tint: tint)
        }
        #else
        filledTimerCapsule(tint: tint)
        #endif
    }

    private func filledTimerCapsule(tint: Color?) -> some View {
        let color = tint ?? .primary
        return background(color.opacity(tint == nil ? 0.06 : 0.14), in: Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(tint == nil ? 0.12 : 0.35), lineWidth: 1)
            }
    }

    /// The timer as the toolbar's principal item. From macOS 26 the timer
    /// draws its own glass, so the toolbar's glass behind the item, which
    /// would take in the padding that centers it, is off.
    @ViewBuilder
    func timerToolbar(_ timer: some View) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            toolbar {
                ToolbarItem(placement: .principal) {
                    timer
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            toolbar {
                ToolbarItem(placement: .principal) {
                    timer
                }
            }
        }
        #else
        toolbar {
            ToolbarItem(placement: .principal) {
                timer
            }
        }
        #endif
    }
}

#if DEBUG
#Preview("Timer") {
    VStack(spacing: 16) {
        TimerCapsule(model: PreviewData.model(PreviewData.stoppedLedger))
        TimerCapsule(model: PreviewData.model())
        TimerCapsule(model: PreviewData.model(Ledger()))
        TimerCapsule(model: PreviewData.model(state: .iCloudUnavailable))
    }
    .fixedSize()
    .padding(40)
}
#endif
#endif

#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A capsule with a round button to start a timer, or with the running
/// timer and a round button to stop it, and a menu of recent projects and
/// tags to start or switch to.
struct TimerCapsule: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    /// Whether toolbar items sit on glass, as on macOS 26 and later when
    /// built with its SDK.
    static var toolbarIsGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    /// As tall as the toolbar's other items.
    static let height: CGFloat = toolbarIsGlass ? 36 : 28
    /// Around the round button, between it and the capsule's edge.
    static let inset: CGFloat = toolbarIsGlass ? 4 : 3

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
                    .frame(height: Self.height - 12)
                    .padding(.leading, 10)
                recentsMenu(recents)
            }
        }
        .padding(.leading, Self.inset)
        .padding(.trailing, recents.isEmpty ? Self.height / 2 - 2 : Self.inset)
        .frame(height: Self.height)
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
                .frame(width: 24, height: Self.height - 2 * Self.inset)
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

/// A white symbol on a colored circle, the timer's start or stop button,
/// filling the capsule's height but for its inset.
private struct TimerGlyph: View {
    let title: String
    let systemImage: String
    let color: Color

    private static let diameter = TimerCapsule.height - 2 * TimerCapsule.inset

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: (Self.diameter * 0.4).rounded(), weight: .heavy))
            .foregroundStyle(.white)
            // The play triangle's weight sits left of its middle.
            .offset(x: systemImage == "play.fill" ? 1 : 0)
            .frame(width: Self.diameter, height: Self.diameter)
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

    /// The timer as the toolbar's principal item, which macOS centers in the
    /// part of the toolbar beside the sidebar. From macOS 26 the timer draws
    /// its own glass, tinted with the project's color, so the toolbar's glass
    /// behind the item is off.
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

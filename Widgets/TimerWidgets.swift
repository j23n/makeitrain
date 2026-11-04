import ActivityKit
import AppIntents
import SwiftUI
import TimerActivity
import WidgetKit

/// The running timer's Live Activity, and controls for Control Center,
/// the Lock Screen and the Action button.
@main
struct TimerWidgets: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
        if #available(iOS 18.0, *) {
            CommandLineControl()
            StopTimerControl()
        }
    }
}

/// The running timer on the Lock Screen and in the Dynamic Island: its
/// project, what it's for, how long it's run, Stop, other entries to switch
/// to and the command line. Once it counts as left running it asks whether
/// it still is, and once stopped it offers to continue it.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                if context.isStale, context.state.end == nil {
                    Label("Still running?", systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.orange)
                }
                TimerHeader(state: context.state, isStale: context.isStale, timerSize: 32)
                ActivityActions(state: context.state, isStale: context.isStale)
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.086, green: 0.094, blue: 0.118).opacity(0.94))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(context.state.lightTint)
                            .frame(width: 10, height: 10)
                        Text(context.state.project)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: context.state, isStale: context.isStale)
                        .font(.system(size: 24, weight: .semibold))
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        TimerDetail(state: context.state, isStale: context.isStale)
                            .padding(.leading, 4)
                        ActivityActions(state: context.state, isStale: context.isStale)
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.lightTint)
                    .frame(width: 12, height: 12)
            } compactTrailing: {
                TimerText(state: context.state, isStale: context.isStale)
                    .frame(maxWidth: 56)
            } minimal: {
                Circle()
                    .fill(context.state.lightTint)
                    .frame(width: 12, height: 12)
            }
            .keylineTint(context.state.lightTint)
        }
    }
}

/// The project over what it's for, and how long it's run.
struct TimerHeader: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool
    let timerSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if state.end == nil {
                        Circle()
                            .fill(state.lightTint)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .strokeBorder(state.lightTint, lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                    Text(state.project)
                        .font(.headline)
                        .lineLimit(1)
                }
                TimerDetail(state: state, isStale: isStale)
                    .padding(.leading, 18)
            }
            Spacer(minLength: 8)
            TimerText(state: state, isStale: isStale)
                .font(.system(size: timerSize, weight: .semibold))
                .frame(maxWidth: 150, alignment: .trailing)
        }
    }
}

/// What the timer is for and when it started, or when it stopped.
struct TimerDetail: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if let end = state.end {
                Text("Stopped · \(state.start, style: .time) to \(end, style: .time)")
            } else if isStale {
                Text("Since \(state.start, format: .dateTime.weekday(.wide).hour().minute())")
            } else if state.detail.isEmpty {
                Text("Since \(state.start, style: .time)")
            } else {
                Text("\(state.detail) · since \(state.start, style: .time)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(1)
    }
}

/// How long the timer has run, counting up while it runs.
struct TimerText: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if let end = state.end {
                Text(timerInterval: state.start...max(state.start, end), pauseTime: end, countsDown: false)
            } else {
                Text(state.start, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(isStale && state.end == nil ? Color.orange : state.end == nil ? state.lightTint : .white.opacity(0.8))
    }
}

/// What can be done from the activity: Stop, two entries to switch to and
/// the command line while the timer runs; stopping when the day usually
/// ends, or now, once it counts as left running; and Continue once it's
/// stopped.
struct ActivityActions: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            if state.end != nil {
                if let line = state.line {
                    Button(intent: StartTimerIntent(line: line)) {
                        Label("Continue", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActivityButtonStyle(prominent: true))
                }
                Button(intent: OpenCommandLineIntent()) {
                    Label("Start Something Else", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActivityButtonStyle(prominent: false))
            } else if isStale {
                if let likelyEnd = state.likelyEnd {
                    Button(intent: StopTimerAtIntent(end: likelyEnd)) {
                        Text("Stop at \(likelyEnd, style: .time)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActivityButtonStyle(prominent: true))
                }
                Button(intent: StopTimerIntent()) {
                    Text("Stop Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActivityButtonStyle(prominent: state.likelyEnd == nil))
            } else {
                Button(intent: StopTimerIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(ActivityButtonStyle(prominent: true))
                .accessibilityLabel(Text("Stop the timer"))
                ForEach(state.switchTo ?? [], id: \.self) { shortcut in
                    Button(intent: StartTimerIntent(line: shortcut.line)) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(shortcut.lightTint)
                                .frame(width: 8, height: 8)
                            Text(shortcut.title)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(ActivityButtonStyle(prominent: false))
                    .accessibilityLabel(Text("Switch to \(shortcut.title)"))
                }
                Button(intent: OpenCommandLineIntent()) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(ActivityButtonStyle(prominent: false, square: true))
                .accessibilityLabel(Text("Open the command line"))
            }
        }
    }
}

/// A button on the activity: white for what it most likely does, a
/// translucent fill otherwise.
struct ActivityButtonStyle: ButtonStyle {
    let prominent: Bool
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: prominent ? .semibold : .medium))
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : 14)
            .frame(width: square ? 44 : nil, height: 44)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? Color.white : Color.white.opacity(0.14))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A label with its icon after its title, as for "Start Something Else ›".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

/// Opens the command line, to start, switch or log time.
@available(iOS 18.0, *)
struct CommandLineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.j23n.TimeTracker.commandLine") {
            ControlWidgetButton(action: OpenCommandLineIntent()) {
                Label("Time Tracker", systemImage: "chevron.right.square")
            }
        }
        .displayName("Command Line")
        .description("Opens the command line.")
    }
}

/// Stops the running timer.
@available(iOS 18.0, *)
struct StopTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.j23n.TimeTracker.stop") {
            ControlWidgetButton(action: StopTimerIntent()) {
                Label("Stop the Timer", systemImage: "stop.circle")
            }
        }
        .displayName("Stop the Timer")
        .description("Stops the running timer.")
    }
}

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
/// project, what it's for, how long it's run, and Stop.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(context.state.tint)
                            .frame(width: 10, height: 10)
                        Text(context.state.project)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(context.state.start, style: .timer)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
                StopButton()
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.tint)
                            .frame(width: 9, height: 9)
                        Text(context.state.project)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.start, style: .timer)
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        StopButton()
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.tint)
                    .frame(width: 10, height: 10)
            } compactTrailing: {
                Text(context.state.start, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 52)
            } minimal: {
                Circle()
                    .fill(context.state.tint)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

/// Stops the timer from the Live Activity, without opening the app.
struct StopButton: View {
    var body: some View {
        Button(intent: StopTimerIntent()) {
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .tint(.primary)
        .accessibilityLabel(Text("Stop the timer"))
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

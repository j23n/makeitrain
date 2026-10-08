#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The menu bar item: an icon, or a dot and the running time, with the
/// project's name if that's chosen, and a mark when something needs
/// correcting this week. It also applies the chosen appearance, and the
/// shortcut that opens the command line over any app, since it's there as
/// long as the app runs.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        label
            .onChange(of: model.preferences.appearance, initial: true) { _, appearance in
                NSApp.appearance = switch appearance {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
            .onChange(of: model.preferences.shortcut, initial: true) { _, shortcut in
                HotKey.shared.register(shortcut) {
                    CommandPanel.shared.toggle(model: model)
                }
            }
    }

    @ViewBuilder
    private var label: some View {
        let preferences = model.preferences
        if let running = model.running, preferences.menuBarShowsTime {
            let project = preferences.menuBarShowsProject ? running.entry.projectID.flatMap { model.ledger.projects[$0]?.name } : nil
            let time = Format.duration(model.duration(of: running))
            Text("\(Image(systemName: needsCorrecting ? "exclamationmark.circle.fill" : "circle.fill")) \(project.map { "\(time) \($0)" } ?? time)")
                .monospacedDigit()
        } else {
            Image(systemName: needsCorrecting ? "clock.badge.exclamationmark" : "clock")
        }
    }

    /// Whether something this week needs correcting, if the mark is wanted.
    /// Calendars aren't read for this, to keep the menu bar light.
    private var needsCorrecting: Bool {
        guard model.preferences.menuBarMarksCorrections else { return false }
        _ = model.revision
        let week = ReportPeriod.week.range(containing: model.today, firstWeekday: model.firstWeekday)
        return !Corrections.find(on: week, ledger: model.ledger, resolved: model.resolved, timeZone: model.environment.timeZone(), now: model.now)
            .filter { !model.preferences.isSkipped($0.id) }
            .isEmpty
    }
}

#if DEBUG
#Preview("Running") {
    MenuBarLabel(model: PreviewData.model())
        .padding()
}

#Preview("Stopped") {
    MenuBarLabel(model: PreviewData.model(PreviewData.stoppedLedger))
        .padding()
}
#endif
#endif

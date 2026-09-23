#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The popover under the menu bar item: the running timer, a quick start,
/// and recent combinations to switch to.
struct MenuBarPopover: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @State private var note = ""
    @State private var projectID: UUID?
    @State private var adjusting: Adjustment?
    @State private var adjustedTime = Date()

    enum Adjustment {
        case start, stop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Notices(model: model)
            runningSection
            Divider()
            quickStart
            recentSection
            Divider()
            footer
        }
        .frame(width: 340)
    }

    // MARK: Running timer

    @ViewBuilder
    private var runningSection: some View {
        if let running = model.running {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    ProjectLabel(ledger: model.ledger, projectID: running.entry.projectID)
                    Spacer()
                    Text(Format.duration(model.duration(of: running)))
                        .font(.system(.title2, design: .rounded))
                        .monospacedDigit()
                }
                if !running.entry.note.isEmpty {
                    Text(running.entry.note)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !running.entry.tags.isEmpty {
                    TagList(tags: running.entry.tags)
                }
                if let adjusting {
                    adjustmentRow(adjusting, running: running)
                } else {
                    HStack {
                        Text("Started \(Format.time(running.start, zone: running.entry.timeZone))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Started Earlier…") {
                            begin(.start, running: running)
                        }
                        Menu("Stop") {
                            Button("Stop at an Earlier Time…") {
                                begin(.stop, running: running)
                            }
                        } primaryAction: {
                            model.stopTimer(undoManager: undoManager)
                        }
                        .fixedSize()
                    }
                    .disabled(model.isReadOnly)
                }
            }
            .padding(12)
        } else {
            Text("No timer running")
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    private func adjustmentRow(_ adjustment: Adjustment, running: ResolvedEntry) -> some View {
        let now = model.now.date
        let range = adjustment == .start
            ? Date.distantPast...now
            : running.start.date...now
        return HStack {
            Text(adjustment == .start ? "Started" : "Stopped")
            DatePicker("", selection: $adjustedTime, in: range, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.field)
                .environment(\.timeZone, Zones.zone(running.entry.timeZone))
            Spacer()
            Button("Cancel") {
                adjusting = nil
            }
            Button(adjustment == .start ? "Change" : "Stop") {
                let time = Timestamp(adjustedTime).wholeSeconds
                switch adjustment {
                case .start: model.setRunningStart(time, undoManager: undoManager)
                case .stop: model.stopTimer(at: time, undoManager: undoManager)
                }
                adjusting = nil
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func begin(_ adjustment: Adjustment, running: ResolvedEntry) {
        adjustedTime = adjustment == .start ? running.start.date : model.now.date
        adjusting = adjustment
    }

    // MARK: Quick start

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What are you working on?", text: $note)
                .textFieldStyle(.roundedBorder)
                .onSubmit(start)
            HStack {
                ProjectPicker(ledger: model.ledger, selection: $projectID)
                    .frame(maxWidth: 220)
                Spacer()
                Button(model.running == nil ? "Start" : "Switch", action: start)
            }
        }
        .padding(12)
        .disabled(model.isReadOnly)
    }

    private func start() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.startTimer(Combination(projectID: projectID, tags: []), note: trimmed, undoManager: undoManager)
        note = ""
    }

    // MARK: Recent combinations

    @ViewBuilder
    private var recentSection: some View {
        let combinations = model.ledger.recentCombinations()
        if !combinations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Switch to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(combinations, id: \.self) { combination in
                    Button {
                        model.startTimer(combination, undoManager: undoManager)
                    } label: {
                        HStack {
                            ProjectLabel(ledger: model.ledger, projectID: combination.projectID)
                            TagList(tags: combination.tags)
                            Spacer()
                            if isRunning(combination) {
                                Image(systemName: "record.circle")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    .disabled(model.isReadOnly)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func isRunning(_ combination: Combination) -> Bool {
        guard let running = model.running else { return false }
        return running.entry.projectID == combination.projectID
            && running.entry.tags.map { $0.lowercased() }.sorted() == combination.tags.map { $0.lowercased() }.sorted()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Open Time Tracker") {
                openWindow(id: WindowID.main)
                NSApp.activate()
            }
            Spacer()
            SettingsLink {
                Text("Settings…")
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }
}

/// A full-width row that highlights under the pointer, like a menu item.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering || configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
                        .padding(.horizontal, 6)
                )
                .onHover { hovering = $0 }
        }
    }
}
#endif

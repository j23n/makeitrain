#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// The running timer, a quick start, and recent combinations to switch to.
struct TimerScreen: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var note = ""
    @State private var projectID: UUID?
    @State private var adjusting: Adjustment?

    enum Adjustment: String, Identifiable {
        case start, stop

        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            List {
                MobileNotices(model: model)
                runningSection
                quickStart
                recentSection
            }
            .navigationTitle("Timer")
            .sheet(item: $adjusting) { adjustment in
                if let running = model.running {
                    AdjustTimeSheet(model: model, running: running, adjustment: adjustment)
                }
            }
        }
    }

    @ViewBuilder
    private var runningSection: some View {
        Section {
            if let running = model.running {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        ProjectLabel(ledger: model.ledger, projectID: running.entry.projectID)
                        Spacer()
                        Text(Format.duration(model.duration(of: running)))
                            .font(.system(.largeTitle, design: .rounded))
                            .monospacedDigit()
                    }
                    if !running.entry.note.isEmpty {
                        Text(running.entry.note)
                            .foregroundStyle(.secondary)
                    }
                    if !running.entry.tags.isEmpty {
                        TagList(tags: running.entry.tags)
                    }
                    Text("Started \(Format.time(running.start, zone: running.entry.timeZone))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    Label("Stop Timer", systemImage: "stop.fill")
                }
                .disabled(model.isReadOnly)
                Button("Started Earlier…") {
                    adjusting = .start
                }
                .disabled(model.isReadOnly)
                Button("Stop at an Earlier Time…") {
                    adjusting = .stop
                }
                .disabled(model.isReadOnly)
            } else {
                Text("No timer running")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickStart: some View {
        Section("Start") {
            TextField("What are you working on?", text: $note)
                .submitLabel(.go)
                .onSubmit(start)
            ProjectPicker(ledger: model.ledger, selection: $projectID)
            Button(model.running == nil ? "Start Timer" : "Switch Timer", action: start)
                .disabled(model.isReadOnly)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let combinations = model.ledger.recentCombinations()
        if !combinations.isEmpty {
            Section("Switch To") {
                ForEach(combinations, id: \.self) { combination in
                    Button {
                        model.startTimer(combination, undoManager: undoManager)
                    } label: {
                        HStack {
                            ProjectLabel(ledger: model.ledger, projectID: combination.projectID)
                            TagList(tags: combination.tags)
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .disabled(model.isReadOnly)
                }
            }
        }
    }

    private func start() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.startTimer(Combination(projectID: projectID, tags: []), note: trimmed, undoManager: undoManager)
        note = ""
    }
}

/// Moves the running timer's start back, or stops it at an earlier time.
struct AdjustTimeSheet: View {
    let model: AppModel
    let running: ResolvedEntry
    let adjustment: TimerScreen.Adjustment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var time: Date

    init(model: AppModel, running: ResolvedEntry, adjustment: TimerScreen.Adjustment) {
        self.model = model
        self.running = running
        self.adjustment = adjustment
        _time = State(initialValue: adjustment == .start ? running.start.date : model.now.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    adjustment == .start ? "Started" : "Stopped",
                    selection: $time,
                    in: adjustment == .start ? Date.distantPast...model.now.date : running.start.date...model.now.date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .environment(\.timeZone, Zones.zone(running.entry.timeZone))
            }
            .navigationTitle(adjustment == .start ? "Started Earlier" : "Stop Earlier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(adjustment == .start ? "Change" : "Stop") {
                        let stamp = Timestamp(time).wholeSeconds
                        switch adjustment {
                        case .start: model.setRunningStart(stamp, undoManager: undoManager)
                        case .stop: model.stopTimer(at: stamp, undoManager: undoManager)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
#endif

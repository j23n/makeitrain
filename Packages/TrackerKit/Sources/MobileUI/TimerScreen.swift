#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Moving the running timer's start back, or stopping it at an earlier time.
enum TimerAdjustment: String, Identifiable {
    case start, stop

    var id: Self { self }
}

/// The running timer, a quick start, and recent combinations to switch to,
/// for the iPhone's Timer tab and the iPad's Timer screen.
struct TimerList: View {
    let model: AppModel
    /// Whether it says what's wrong with storage. On iPad the sidebar does.
    var showsNotices = true
    @Environment(\.undoManager) private var undoManager
    @State private var note = ""
    @State private var projectID: UUID?
    @State private var adjusting: TimerAdjustment?

    var body: some View {
        List {
            if showsNotices {
                MobileNotices(model: model)
            }
            runningSection
            quickStart
            recentSection
        }
        .sheet(item: $adjusting) { adjustment in
            if let running = model.running {
                AdjustTimeSheet(model: model, running: running, adjustment: adjustment)
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
                        TagList(tags: running.entry.tags, links: model.ledger.issueLinks(tags: running.entry.tags, projectID: running.entry.projectID))
                    }
                    Text("Started \(Format.time(running.start, zone: running.entry.timeZone))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                // Red, as the stop buttons in the Mac's and the iPad's
                // toolbars are.
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    Label("Stop Timer", systemImage: "stop.fill")
                }
                .tint(.red)
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
                    // The running timer's project and tags are marked, and
                    // can't be picked again, as in the timer's menus on the
                    // Mac and the iPad.
                    let running = model.running.map { combination.matches($0.entry) } ?? false
                    Button {
                        model.startTimer(combination, undoManager: undoManager)
                    } label: {
                        HStack {
                            ProjectLabel(ledger: model.ledger, projectID: combination.projectID)
                            TagList(
                                tags: combination.tags,
                                links: model.ledger.issueLinks(tags: combination.tags, projectID: combination.projectID),
                                interactive: false
                            )
                            Spacer()
                            if running {
                                RunningIcon()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .disabled(model.isReadOnly || running)
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
    let adjustment: TimerAdjustment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var time: Date

    init(model: AppModel, running: ResolvedEntry, adjustment: TimerAdjustment) {
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

#if DEBUG
#Preview("Started Earlier") {
    let model = PreviewData.model()
    return AdjustTimeSheet(model: model, running: model.running!, adjustment: .start)
}

#Preview("Stop Earlier") {
    let model = PreviewData.model()
    return AdjustTimeSheet(model: model, running: model.running!, adjustment: .stop)
}
#endif
#endif

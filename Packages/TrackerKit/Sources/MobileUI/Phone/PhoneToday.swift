#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import WideUI

/// Today: the day so far on an hour grid, what needs correcting on it,
/// and the command line over the tab bar.
struct PhoneToday: View {
    let model: AppModel
    let router: PhoneRouter
    @State private var editing: ResolvedEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhoneHeader(title: "Today", subtitle: subtitle) {
                if !router.today.corrections.isEmpty {
                    Button {
                        router.showWeek(model.today, correction: router.today.corrections.first?.id, firstWeekday: model.firstWeekday)
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(Theme.amber).frame(width: 7, height: 7)
                            Text("\(router.today.corrections.count) to correct")
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.amberText)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Capsule().fill(Theme.amberFill))
                        .overlay(Capsule().strokeBorder(Theme.amberLine))
                    }
                    .buttonStyle(.plain)
                }
            }
            if router.today.entries(on: model.today).isEmpty, router.today.suggestedAdditions.isEmpty {
                PhoneEmptyDay()
            } else {
                PhoneDayGrid(model: model, week: router.today, day: model.today) { entry in
                    editing = entry
                } onCorrection: { preview in
                    router.showWeek(preview.correction.day, correction: preview.id, firstWeekday: model.firstWeekday)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            PhoneCommandBar(
                model: model,
                placeholder: model.running == nil ? "start a timer or log time" : "switch, stop or log time",
                open: { router.openCommandLine() }
            )
        }
        .sheet(item: $editing) { entry in
            PhoneEntrySheet(model: model, entryID: entry.id)
        }
    }

    /// "Monday 5 October · 3:00 so far".
    private var subtitle: Text {
        let total = model.dayTotals.total(on: model.today, now: model.now)
        return Text("\(Format.fullDay(model.today)) · ")
            + Text(Format.duration(total)).foregroundColor(Theme.text)
            + Text(" so far")
    }
}

/// A screen's large title, with a line under it and buttons beside it.
struct PhoneHeader<Trailing: View>: View {
    let title: String
    var subtitle: Text?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    subtitle
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text2)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            trailing
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

/// A day with nothing on it yet.
struct PhoneEmptyDay: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 30))
                .foregroundStyle(Theme.text3)
            Text("Nothing logged yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Type a project in the line below to start a timer.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// An entry as a line to change by typing, such as "2 oct 13:30-16:30
/// web #12 Fix login", and what else can be done with it.
struct PhoneEntrySheet: View {
    let model: AppModel
    let entryID: UUID
    @State private var line: EntryLineModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, entryID: UUID) {
        self.model = model
        self.entryID = entryID
        _line = State(initialValue: EntryLineModel(model: model))
    }

    private var entry: ResolvedEntry? {
        model.resolved.first { $0.id == entryID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    content(entry)
                } else {
                    Text("This entry was deleted.")
                        .foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle(entry.map { Format.day($0.entry.day) } ?? "Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .disabled(model.isReadOnly || line.isUnchanged)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            line.show(entryID)
        }
    }

    private func content(_ entry: ResolvedEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CommandField(
                            entryLine: line,
                            fontSize: 15,
                            focusesWithWindow: true,
                            onSubmit: { apply() },
                            onCancel: { dismiss() }
                        )
                        .frame(height: 44)
                        Text(Format.duration(model.duration(of: entry)))
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(line.refused ? Theme.amber : Theme.strongLine))
                    if !line.suggestions.isEmpty {
                        SuggestionStrip(suggestions: line.suggestions, highlighted: line.highlightedSuggestion, ledger: model.ledger, showsKeys: false) { index in
                            line.acceptSuggestion(at: index)
                        }
                    }
                    EntryLineGuide(model: model, line: line)
                }
                actions(entry)
            }
            .padding(16)
        }
    }

    private func actions(_ entry: ResolvedEntry) -> some View {
        VStack(spacing: 0) {
            if entry.isRunning {
                row("Stop", systemImage: "stop.fill") {
                    model.stopTimer(undoManager: undoManager)
                    dismiss()
                }
            } else {
                row("Continue it now", systemImage: "play.fill") {
                    model.startTimer(EntryDraft(entry.entry), undoManager: undoManager)
                    dismiss()
                }
                row("Duplicate", systemImage: "plus.square.on.square") {
                    model.duplicateEntries([entry.id], undoManager: undoManager)
                    dismiss()
                }
            }
            if EntrySplit.range(of: entry, now: model.now) != nil {
                row("Split in the middle", systemImage: "scissors") {
                    model.splitEntry(entry.id, at: Timestamp(EntrySplit.suggestedTime(for: entry, now: model.now)), undoManager: undoManager)
                    dismiss()
                }
            }
            row("Delete", systemImage: "trash", destructive: true) {
                model.deleteEntries([entry.id], undoManager: undoManager)
                dismiss()
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
        .disabled(model.isReadOnly)
    }

    private func row(_ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer()
            }
            .font(.system(size: 15))
            .foregroundStyle(destructive ? Theme.now : Theme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func apply() {
        guard entry != nil else { return }
        if line.apply(undoManager: undoManager) {
            dismiss()
        }
    }
}
#endif

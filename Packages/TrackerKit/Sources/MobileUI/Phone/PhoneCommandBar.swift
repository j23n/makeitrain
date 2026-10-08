#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import WideUI

/// The command line floating over the tab bar: the running timer, what to
/// type, and Stop. Tapping it opens the command line.
struct PhoneCommandBar: View {
    let model: AppModel
    let placeholder: String
    let open: () -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 8) {
            if let running = model.running {
                Button(action: open) {
                    RunningTimerLabel(model: model, running: running)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                Rectangle()
                    .fill(Theme.strongLine)
                    .frame(width: 1, height: 28)
            }
            Button(action: open) {
                HStack(spacing: 7) {
                    Text("›")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(placeholder)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.text3)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Command line"))
            .accessibilityHint(Text(placeholder))
            if model.running != nil {
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Theme.inverseText)
                        .frame(width: 11, height: 11)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inverse))
                }
                .buttonStyle(.plain)
                .disabled(model.isReadOnly)
                .accessibilityLabel(Text("Stop the timer"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 17).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.strongLine))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// The command line, open over the screen: the field, what Return would
/// do, a button for it, and words to add to the line. On the Month tab it
/// can read a report instead, such as "acme sep by tag".
struct PhoneCommandSheet: View {
    let model: AppModel
    let router: PhoneRouter
    @Bindable var line: CommandLineModel
    let close: () -> Void
    @State private var reportText = ""
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if router.tab == .month {
                Picker("Mode", selection: Binding(get: { router.commandMode }, set: { router.commandMode = $0; router.focusRequest += 1 })) {
                    Text("Report").tag(PhoneCommandMode.report)
                    Text("Time").tag(PhoneCommandMode.command)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            if router.commandMode == .report {
                reportLine
            } else {
                commandLine
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.raised))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.strongLine))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .padding(.horizontal, 10)
        .onAppear {
            reportText = router.month.typed
        }
    }

    // MARK: Time

    @ViewBuilder
    private var commandLine: some View {
        if let running = model.running {
            HStack(spacing: 7) {
                Circle().fill(Theme.now).frame(width: 7, height: 7)
                Text(Format.duration(model.duration(of: running)))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                Text(runningTitle(running))
                    .lineLimit(1)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        field(text: $line.text, CommandField(
            line: line,
            placeholder: CommandText.placeholder(running: model.running),
            fontSize: 17,
            focusesWithWindow: true,
            focusRequest: router.focusRequest,
            onSubmit: { alternate in submit(alternate: alternate) },
            onCancel: close
        ))
        if case .find? = line.reading.primary {
            foundEntries
        } else {
            CommandPreviewView(line: line, showsKey: false)
                .font(.system(size: 15))
        }
        actions
        additions
    }

    private func runningTitle(_ running: ResolvedEntry) -> String {
        let project = running.entry.projectID.flatMap { model.ledger.projects[$0]?.name } ?? "Unassigned"
        return running.entry.note.isEmpty ? project : "\(project) · \(running.entry.note)"
    }

    /// A field for the typed report.
    private func field(text: Binding<String>, placeholder: String, reading: CommandReading, submit: @escaping (_ alternate: Bool) -> Void) -> some View {
        field(text: text, CommandField(
            text: text,
            placeholder: placeholder,
            reading: reading,
            ledger: model.ledger,
            fontSize: 17,
            focusesWithWindow: true,
            focusRequest: router.focusRequest,
            onSubmit: submit,
            onCancel: close
        ))
    }

    /// A field with the prompt before it and, once something's typed, a
    /// button that clears it.
    private func field(text: Binding<String>, _ input: CommandField) -> some View {
        HStack(spacing: 10) {
            Text("›")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            input
                .frame(height: 56)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
    }

    /// The button for what Return does, and for what the line could also
    /// mean, such as logging it as done.
    @ViewBuilder
    private var actions: some View {
        if let command = line.reading.primary, line.preview != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        submit(alternate: false)
                    } label: {
                        Text(CommandText.verb(command, running: model.running))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(Theme.inverseText)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.inverse))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isReadOnly)
                }
                if let alternate = line.reading.alternate {
                    Button {
                        submit(alternate: true)
                    } label: {
                        Text(CommandText.title(alternate, running: model.running, now: model.environment.now(), zone: model.environment.timeZone()))
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(Theme.text)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.strongLine))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isReadOnly)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func submit(alternate: Bool) {
        if line.submit(alternate: alternate, undoManager: undoManager) {
            close()
        }
    }

    /// What "find" turned up, the latest first. Tapping one shows its day.
    private var foundEntries: some View {
        VStack(spacing: 0) {
            ForEach(line.found.prefix(8)) { entry in
                Button {
                    router.showWeek(entry.entry.day, firstWeekday: model.firstWeekday)
                    router.week.selectedEntry = entry.id
                    close()
                } label: {
                    HStack(spacing: 10) {
                        TintDot(model.ledger.tint(ofProject: entry.entry.projectID), size: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.entry.note.isEmpty ? model.ledger.projectTitle(entry.entry.projectID) : entry.entry.note)
                                .lineLimit(1)
                            Text("\(Format.day(entry.entry.day)) · \(Format.time(entry.start, zone: entry.entry.timeZone))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text3)
                        }
                        Spacer(minLength: 8)
                        Text(Format.duration(model.duration(of: entry)))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text2)
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            if line.found.isEmpty, !line.text.isEmpty {
                Text("Nothing found.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Words to add to the line: what could replace the word being typed,
    /// a start, a time ago, a tag, and the completion of a project's name.
    /// With nothing typed, the lines run lately.
    private var additions: some View {
        let chips = line.chips
        return Group {
            if !chips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(line.text.isEmpty ? "Run again" : "Add to the line")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                    FlowLayout(spacing: 8) {
                        ForEach(chips) { chip in
                            Button {
                                line.apply(chip)
                                router.focusRequest += 1
                            } label: {
                                ChipLabel(chip, size: .touch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }

    // MARK: Report

    private var query: ReportQuery {
        ReportQuery.read(reportText, ledger: model.ledger, today: model.today, firstWeekday: model.firstWeekday)
    }

    @ViewBuilder
    private var reportLine: some View {
        let query = self.query
        field(text: $reportText, placeholder: "acme last month by tag", reading: query.reading, submit: { _ in showReport() })
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Show").fontWeight(.semibold)
                Text(reportTitle(query))
                    .foregroundStyle(Theme.text4)
            }
            .font(.system(size: 15))
            Text("Clients, projects or tags, a period such as sep or 1-15 sep, and by client, project or tag.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentFill)
        Button(action: showReport) {
            Text("Show")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Theme.inverseText)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.inverse))
        }
        .buttonStyle(.plain)
        .padding(16)
    }

    /// Such as "Acme, Sep 1 – 30, 2026, by tag".
    private func reportTitle(_ query: ReportQuery) -> String {
        let names = query.clients.compactMap { model.ledger.clients[$0]?.name }
            + query.projects.compactMap { model.ledger.projects[$0]?.name }
            + query.tags.sorted()
        let what = names.isEmpty ? "everything" : names.sorted().formatted(.list(type: .and))
        let range = query.range ?? router.month.range
        let grouping = query.grouping ?? router.month.grouping
        return "\(what), \(Format.days(range)), by \(grouping.rawValue)"
    }

    private func showReport() {
        router.month.apply(query)
        close()
    }
}
#endif

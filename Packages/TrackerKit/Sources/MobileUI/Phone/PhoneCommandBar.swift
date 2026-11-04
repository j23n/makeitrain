#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import WideUI

/// The command line floating over the tab bar: the running timer, on two
/// lines with its project's color, and Stop, or what to type. Tapping it
/// opens the command line.
struct PhoneCommandBar: View {
    let model: AppModel
    let placeholder: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Text("›")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    if let running = model.running {
                        runningLabel(running)
                    } else {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Theme.text3)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(model.running.map { "Command line. Running: \(model.ledger.projectTitle($0.entry.projectID)), \(Format.duration(model.duration(of: $0)))" } ?? "Command line"))
            .accessibilityHint(Text(placeholder))
            if model.running != nil {
                StopTimerButton(model: model, size: 44, shortcut: false)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, model.running == nil ? 14 : 8)
        .frame(height: model.running == nil ? 54 : 62)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.strongLine))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// The running timer: a bar in its project's color, the project over
    /// its tags and note, and how long it's run.
    private func runningLabel(_ running: ResolvedEntry) -> some View {
        let entry = running.entry
        let detail = (entry.tags.map(Tags.typed) + [entry.note]).filter { !$0.isEmpty }.joined(separator: " ")
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.projectID == nil ? Theme.text3 : model.ledger.tint(ofProject: entry.projectID).ink)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.projectID.flatMap { model.ledger.projects[$0]?.name } ?? "Unassigned")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(entry.projectID == nil ? Theme.text2 : Theme.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(Format.duration(model.duration(of: running)))
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
    }
}

/// The command line, open over the screen at its bottom, with the field
/// right above the keyboard and over it the running timer and what the line
/// lists: the latest entries to start again, the earlier entries it could
/// start again, what it does as typed, or what "find" found. On the Month tab it can read a
/// report instead, such as "acme sep by tag".
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
            RunningCard(model: model, running: running, touch: true)
            Divider().overlay(Theme.line)
        }
        // As tall as what's listed, scrolling when the keyboard leaves too
        // little room for it.
        ViewThatFits(in: .vertical) {
            details
            ScrollView {
                details
            }
        }
        Divider().overlay(Theme.line)
        field(text: $line.text, CommandField(
            line: line,
            placeholder: CommandText.placeholder,
            fontSize: 17,
            focusesWithWindow: true,
            focusRequest: router.focusRequest,
            onSubmit: { alternate in submit(alternate: alternate) },
            onCancel: close
        ))
    }

    private var details: some View {
        CommandDetails(
            line: line,
            continuesField: false,
            size: .touch,
            select: show,
            submit: { submit(alternate: $0) },
            startAgain: { entry in
                line.startAgain(entry, undoManager: undoManager)
                close()
            },
            refocus: { router.focusRequest += 1 }
        )
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

    private func submit(alternate: Bool) {
        if line.submit(alternate: alternate, undoManager: undoManager) {
            close()
        }
    }

    /// Shows an entry the line listed on its day of the week.
    private func show(_ entry: ResolvedEntry) {
        router.showWeek(entry.entry.day, firstWeekday: model.firstWeekday)
        router.week.selectedEntry = entry.id
        close()
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

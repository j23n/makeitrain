#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// A week: its days in a strip with their time, the chosen day on an hour
/// grid with what needs correcting drawn in place, and the corrections one
/// at a time in a panel at the bottom.
struct PhoneWeek: View {
    let model: AppModel
    let router: PhoneRouter
    @State private var editing: ResolvedEntry?

    private var week: WeekModel { router.week }

    private var days: [LocalDate] {
        var days: [LocalDate] = []
        var day = week.days.lowerBound
        while day <= week.days.upperBound {
            days.append(day)
            day = day.adding(days: 1)
        }
        return days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dayStrip
            PhoneDayGrid(model: model, week: week, day: router.weekDay, gutter: 44) { entry in
                editing = entry
            } onCorrection: { preview in
                week.selectedCorrection = preview.id
            }
            .id(router.weekDay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if let preview = week.selectedPreview {
                PhoneCorrectionPanel(model: model, week: week, preview: preview) { day in
                    router.weekDay = day
                }
            } else {
                PhoneCommandBar(
                    model: model,
                    placeholder: model.running == nil ? "start a timer or log time" : "switch, stop or log time",
                    open: { router.openCommandLine() }
                )
            }
        }
        .sheet(item: $editing) { entry in
            PhoneEntrySheet(model: model, entryID: entry.id)
        }
        .onChange(of: week.selectedCorrection) { _, id in
            if let correction = week.corrections.first(where: { $0.id == id }), correction.day != router.weekDay {
                router.weekDay = correction.day
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Week")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                if !week.days.contains(model.today) {
                    Button("Today") {
                        show(model.today)
                    }
                    .font(.system(size: 16))
                    .padding(.trailing, 4)
                }
                stepButton("chevron.left", "Previous week", -7)
                stepButton("chevron.right", "Next week", 7)
            }
            .padding(.leading, 20)
            .padding(.trailing, 8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.days(week.days))
                    .foregroundStyle(Theme.text2)
                Spacer()
                totals
            }
            .font(.system(size: 14))
            .padding(.horizontal, 20)
        }
        .padding(.top, 6)
    }

    private func stepButton(_ systemImage: String, _ title: String, _ days: Int) -> some View {
        Button {
            show(router.weekDay.adding(days: days))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(title))
    }

    private func show(_ day: LocalDate) {
        router.weekDay = day
        week.show(ReportPeriod.week.range(containing: day, firstWeekday: model.firstWeekday))
    }

    /// The week's total, and what it would be with the corrections.
    @ViewBuilder
    private var totals: some View {
        let totals = week.totals
        if let corrected = totals.corrected {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Format.duration(totals.total))
                    .font(.system(size: 13))
                    .strikethrough(true, color: Theme.amber)
                    .foregroundStyle(Theme.text3)
                Text(Format.duration(corrected))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(Format.duration(totals.total)), \(Format.duration(corrected)) with corrections"))
        } else {
            Text(Format.duration(totals.total))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
        }
    }

    // MARK: Days

    private var dayStrip: some View {
        let corrected = Dictionary(grouping: week.corrections, by: \.day)
        return HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                let total = week.total(on: day)
                let selected = day == router.weekDay
                let count = corrected[day]?.count ?? 0
                Button {
                    router.weekDay = day
                } label: {
                    VStack(spacing: 1) {
                        Text(Format.weekday(day).prefix(1))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text3)
                        Text("\(day.day)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(day == model.today ? Theme.accent : Theme.text)
                        Text(total > 0 ? Format.duration(total) : "—")
                            .font(.system(size: 11.5, weight: total > Corrections.longest ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(total > Corrections.longest ? Theme.amberText : Theme.text3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.accentFill : Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Circle().fill(Theme.amber).frame(width: 6, height: 6).padding(6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(dayLabel(day, total: total, corrections: count)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayLabel(_ day: LocalDate, total: Int64, corrections: Int) -> String {
        var label = "\(Format.fullDay(day)), \(total > 0 ? Format.duration(total) : "nothing logged")"
        if corrections > 0 {
            label += ", \(corrections) \(corrections == 1 ? "correction" : "corrections")"
        }
        return label
    }
}

/// The selected correction, at the bottom of the week: what and when,
/// what's wrong, what its suggestion changes, and its fixes.
struct PhoneCorrectionPanel: View {
    let model: AppModel
    let week: WeekModel
    let preview: CorrectionPreview
    /// Shows a correction's day.
    let showDay: (LocalDate) -> Void
    @Environment(\.undoManager) private var undoManager

    private var correction: Correction { preview.correction }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Capsule()
                .fill(Theme.strongLine)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                CorrectionMarker(preview.number)
                Text(CorrectionText.label(correction, model: model))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(preview.number) of \(week.previews.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                    .monospacedDigit()
                stepButton("chevron.left", "Previous correction", -1)
                stepButton("chevron.right", "Next correction", 1)
            }
            Text(CorrectionText.title(correction, model: model))
                .font(.system(size: 16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let explanation = CorrectionText.explanation(correction, model: model), preview.diff.entries.isEmpty {
                Text(explanation)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !preview.diff.entries.isEmpty {
                changes
            }
            fixes
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Theme.panel)
                .shadow(color: .black.opacity(0.12), radius: 14, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Correction \(preview.number) of \(week.previews.count)"))
    }

    private func stepButton(_ systemImage: String, _ title: String, _ step: Int) -> some View {
        Button {
            week.moveSelection(by: step)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    /// What the suggestion changes, entry by entry.
    private var changes: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(preview.diff.entries.enumerated()), id: \.offset) { _, change in
                if let after = change.after, !after.isDeleted {
                    GridRow {
                        HStack(spacing: 7) {
                            Text(after.note.isEmpty ? model.ledger.projectTitle(after.projectID) : after.note)
                                .lineLimit(1)
                            if change.isNew {
                                Text("new")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.amberText)
                                    .padding(.horizontal, 6)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.amberFill))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            if let before = change.before {
                                ChangedText(old: span(before) == span(after) ? nil : span(before), new: span(after), size: 14)
                            } else {
                                Text(span(after))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.amberText)
                            }
                        }
                        .monospacedDigit()
                    }
                }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
    }

    private func span(_ entry: TimeEntry) -> String {
        let zone = entry.timeZone
        return "\(Format.time(entry.start, zone: zone))–\(entry.end.map { Format.time($0, zone: zone) } ?? "now")"
    }

    private var fixes: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(correction.fixes.prefix(2).enumerated()), id: \.offset) { index, fix in
                    Button {
                        apply(fix)
                    } label: {
                        Text(CorrectionText.fixTitle(fix, in: correction, model: model))
                            .font(.system(size: 15, weight: index == 0 ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(index == 0 ? Theme.inverseText : Theme.text)
                            .background(RoundedRectangle(cornerRadius: 13).fill(index == 0 ? Theme.inverse : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(index == 0 ? Color.clear : Theme.strongLine))
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(index == 0 ? 1.4 : 1)
                }
            }
            HStack(spacing: 16) {
                if case let .noProject(id) = correction.kind {
                    Menu("Choose a project") {
                        ForEach(model.ledger.pickerProjects()) { project in
                            Button(model.ledger.projectTitle(project.id)) {
                                apply(.assign(id: id, projectID: project.id))
                            }
                        }
                    }
                }
                ForEach(Array(correction.fixes.dropFirst(2).enumerated()), id: \.offset) { _, fix in
                    Button(CorrectionText.fixTitle(fix, in: correction, model: model)) {
                        apply(fix)
                    }
                }
                Spacer()
                Button("Skip") {
                    week.selectedCorrection = preview.id
                    week.skipSelected()
                }
                .foregroundStyle(Theme.text2)
            }
            .font(.system(size: 14))
        }
        .disabled(model.isReadOnly)
    }

    private func apply(_ fix: CorrectionFix) {
        model.apply(fix, undoManager: undoManager)
        week.reload()
        if let next = week.selectedPreview {
            showDay(next.correction.day)
        }
    }
}
#endif

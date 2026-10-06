#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit

/// One day on an hour grid, as Today and the Week tab show it: the
/// entries as blocks in their projects' colors, and what the corrections
/// would change drawn over them, as on the Mac: changed times struck
/// through, what would be added as dashed outlines, time counted twice
/// hatched, and numbered markers.
struct PhoneDayGrid: View {
    let model: AppModel
    let week: WeekModel
    let day: LocalDate
    var hourHeight: CGFloat = 40
    var gutter: CGFloat = 52
    /// Whether the markers of corrections show.
    var showsMarkers = true
    let onSelect: (ResolvedEntry) -> Void
    var onCorrection: (CorrectionPreview) -> Void = { _ in }

    private var zone: String { model.environment.timeZone() }

    var body: some View {
        let blocks = DayLayout.blocks(on: day, entries: week.entries(on: day), now: model.now)
        let hours = hourRange(blocks)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            Color.clear.frame(height: hourHeight).id(hour)
                        }
                    }
                    gutterLabels(hours)
                    GeometryReader { geometry in
                        let width = geometry.size.width - gutter - 16
                        ZStack(alignment: .topLeading) {
                            hourLines(hours, width: width)
                            ForEach(blocks) { block in
                                blockView(block, hours: hours, width: width)
                            }
                            ghosts(hours, width: width)
                            overlaps(hours, width: width)
                            longEntries(hours, width: width)
                            if showsMarkers {
                                markers(hours, width: width)
                            }
                            nowLine(hours, width: width)
                        }
                        .offset(x: gutter)
                    }
                }
                .frame(height: CGFloat(hours.count) * hourHeight + 16)
                .padding(.top, 8)
            }
            .onAppear {
                let target = day == model.today
                    ? max(hours.lowerBound, model.now.local(in: zone).hour - 2)
                    : (blocks.map { $0.startSecond / 3600 }.min() ?? 8)
                proxy.scrollTo(min(max(target, hours.lowerBound), hours.upperBound - 1), anchor: .top)
            }
        }
    }

    /// 7:00 to 19:00, widened to any entry, suggestion or the current time.
    private func hourRange(_ blocks: [DayBlock]) -> Range<Int> {
        var first = 7
        var last = 19
        for block in blocks {
            first = min(first, block.startSecond / 3600)
            last = max(last, Int((Double(block.endSecond) / 3600).rounded(.up)))
        }
        for addition in week.suggestedAdditions where addition.entry.day == day {
            let zone = addition.entry.timeZone
            first = min(first, addition.entry.start.local(in: zone).hour)
            if let end = addition.entry.end {
                last = max(last, end.local(in: zone).hour + 1)
            }
        }
        if day == model.today {
            let hour = model.now.local(in: zone).hour
            first = min(first, hour)
            last = max(last, hour + 1)
        }
        return max(0, first)..<min(24, max(last, first + 1))
    }

    private func y(_ second: Int, _ hours: Range<Int>) -> CGFloat {
        (CGFloat(second) / 3600 - CGFloat(hours.lowerBound)) * hourHeight
    }

    private func y(_ time: Timestamp, zone: String, _ hours: Range<Int>) -> CGFloat {
        let local = time.local(in: zone)
        let second = local.date == day ? local.millisecondOfDay / 1000 : (local.date < day ? 0 : 86400)
        return y(second, hours)
    }

    // MARK: Grid

    private func gutterLabels(_ hours: Range<Int>) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(hours, id: \.self) { hour in
                Text(Format.hour(hour))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
                    .offset(y: max(0, CGFloat(hour - hours.lowerBound) * hourHeight - 7))
                    .padding(.trailing, 10)
            }
            if day == model.today {
                Text(Format.time(model.now, zone: zone))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.nowText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.now))
                    .offset(y: max(0, y(model.now, zone: zone, hours) - 9))
                    .padding(.trailing, 4)
            }
        }
        .frame(width: gutter, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    private func hourLines(_ hours: Range<Int>, width: CGFloat) -> some View {
        ForEach(hours, id: \.self) { hour in
            Rectangle()
                .fill(Theme.hourLine)
                .frame(width: width, height: 1)
                .offset(y: y(hour * 3600, hours))
        }
    }

    // MARK: Blocks

    private func blockView(_ block: DayBlock, hours: Range<Int>, width: CGFloat) -> some View {
        let columnWidth = (width - 8) / CGFloat(max(block.columns, 1))
        let top = y(block.startSecond, hours)
        let height = max(y(block.endSecond, hours) - top, 20)
        let entry = block.entry
        let change = week.suggestedChange(of: entry.id)
        return PhoneEntryBlock(
            model: model,
            entry: entry,
            height: height,
            selected: week.selectedEntry == entry.id,
            change: change.map { ($0.before, $0.after) },
            overnight: overnightNote(entry)
        )
        .frame(width: columnWidth - (block.columns > 1 ? 2 : 0), height: height)
        .offset(x: 4 + CGFloat(block.column) * columnWidth, y: top)
        .onTapGesture {
            week.selectedEntry = entry.id
            onSelect(entry)
        }
        .contextMenu {
            PhoneEntryMenu(model: model, entry: entry)
        }
    }

    /// "ran overnight · 19:25" on a block that did.
    private func overnightNote(_ entry: ResolvedEntry) -> String? {
        for preview in week.previews {
            if case let .ranLong(id, overnight) = preview.correction.kind, id == entry.id {
                let length = Format.duration(model.duration(of: entry))
                if entry.isRunning { return "running \(length)" }
                return overnight ? "ran overnight · \(length)" : "ran \(length)"
            }
        }
        return nil
    }

    // MARK: Corrections

    /// What suggestions would add: calendar events and parts of split
    /// entries, dashed.
    private func ghosts(_ hours: Range<Int>, width: CGFloat) -> some View {
        ForEach(week.suggestedAdditions.filter { $0.entry.day == day }) { addition in
            let entry = addition.entry
            let zone = entry.timeZone
            let top = y(entry.start, zone: zone, hours)
            let bottom = y(entry.end ?? model.now, zone: zone, hours)
            let times = "\(Format.time(entry.start, zone: zone))–\(entry.end.map { Format.time($0, zone: zone) } ?? "now")"
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if addition.isEvent {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(times + calendarName(entry))
                    } else {
                        Text(entry.note.isEmpty ? model.ledger.projectTitle(entry.projectID) : entry.note)
                        Text(times)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.amberText)
                        Spacer(minLength: 2)
                        Text("new")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.amberText)
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.text3)
                if addition.isEvent {
                    Text(entry.note.isEmpty ? model.ledger.projectTitle(entry.projectID) : entry.note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text4)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(width: width - 8, height: max(bottom - top, 22), alignment: .topLeading)
            .background {
                if !addition.isEvent {
                    RoundedRectangle(cornerRadius: 9).fill(model.ledger.tint(ofProject: entry.projectID).fill)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(addition.isEvent ? Theme.ghost : Theme.amber, style: StrokeStyle(lineWidth: addition.isEvent ? 1 : 1.5, dash: [4, 3]))
            )
            .clipped()
            .offset(x: 4, y: top)
            .onTapGesture {
                if let preview = week.previews.first(where: { $0.number == addition.number }) {
                    week.selectedCorrection = preview.id
                    onCorrection(preview)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Suggested: \(entry.note), \(times)"))
        }
    }

    /// " · Work calendar", for an event from a project's calendar.
    private func calendarName(_ entry: TimeEntry) -> String {
        guard let projectID = entry.projectID, let calendar = model.linkedCalendar(ofProject: projectID) else { return "" }
        return " · \(calendar.title) calendar"
    }

    /// Time two entries both count, hatched.
    private func overlaps(_ hours: Range<Int>, width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            if case let .overlap(overlap) = preview.correction.kind,
               let earlier = model.ledger.entries[overlap.earlier], let later = model.ledger.entries[overlap.later],
               let earlierEnd = earlier.end ?? (earlier.id == model.running?.id ? model.now : nil) {
                let zone = later.timeZone
                let top = y(later.start, zone: zone, hours)
                let bottom = y(min(earlierEnd, later.end ?? model.now), zone: zone, hours)
                Hatching()
                    .frame(width: width - 8, height: max(bottom - top, 3))
                    .overlay(alignment: .top) { Rectangle().fill(Theme.amber).frame(height: 1.5) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.amber).frame(height: 1.5) }
                    .offset(x: 4, y: top)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Where an entry that ran long likely ended: a line at the suggested
    /// time.
    private func longEntries(_ hours: Range<Int>, width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            if case let .ranLong(id, _) = preview.correction.kind, let entry = model.ledger.entries[id],
               case let .end(_, suggested)? = preview.correction.suggestion {
                let line = y(suggested, zone: entry.timeZone, hours)
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.amber).frame(height: 1.5)
                    Text("\(Format.time(suggested, zone: entry.timeZone))?")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.markerText)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(Theme.marker))
                }
                .frame(width: width - 8)
                .offset(x: 4, y: line - 10)
                .allowsHitTesting(false)
            }
        }
    }

    /// The corrections' numbers, at the top right of what they're about.
    private func markers(_ hours: Range<Int>, width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            CorrectionMarker(preview.number)
                .background(Circle().strokeBorder(Theme.background, lineWidth: 2).padding(-2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .offset(x: width - 30, y: max(markerTop(preview, hours) - 22, -12))
                .onTapGesture {
                    week.selectedCorrection = preview.id
                    onCorrection(preview)
                }
                .accessibilityLabel(Text("Correction \(preview.number)"))
                .accessibilityAddTraits(.isButton)
        }
    }

    private func markerTop(_ preview: CorrectionPreview, _ hours: Range<Int>) -> CGFloat {
        switch preview.correction.kind {
        case let .overlap(overlap):
            let entry = model.ledger.entries[overlap.earlier]
            let later = model.ledger.entries[overlap.later]
            if let entry, entry.day == day {
                return y(entry.start, zone: entry.timeZone, hours)
            }
            return later.map { y($0.start, zone: $0.timeZone, hours) } ?? 0
        case let .ranLong(id, _), let .noProject(id):
            return model.ledger.entries[id].map { y($0.start, zone: $0.timeZone, hours) } ?? 0
        case let .notLogged(entry):
            return y(entry.start, zone: entry.timeZone, hours)
        }
    }

    /// The red line at the current time, on today.
    @ViewBuilder
    private func nowLine(_ hours: Range<Int>, width: CGFloat) -> some View {
        if day == model.today {
            let top = y(model.now, zone: zone, hours)
            HStack(spacing: 0) {
                Circle().fill(Theme.now).frame(width: 10, height: 10)
                Rectangle().fill(Theme.now).frame(height: 2)
            }
            .frame(width: width + 5)
            .offset(x: -5, y: top - 5)
            .allowsHitTesting(false)
        }
    }
}

/// One entry on the iPhone's grid: its title, times and tags in its
/// project's tint, outlined when selected, dashed amber when a suggestion
/// would change it.
struct PhoneEntryBlock: View {
    let model: AppModel
    let entry: ResolvedEntry
    let height: CGFloat
    let selected: Bool
    let change: (before: TimeEntry, after: TimeEntry)?
    let overnight: String?

    private var unassigned: Bool { entry.entry.projectID == nil }
    private var tint: ProjectTint { model.ledger.tint(ofProject: entry.entry.projectID) }
    private var zone: String { entry.entry.timeZone }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, height < 34 ? 0 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height < 34 ? .leading : .topLeading)
            .background(shape.fill(fill))
            .overlay(border)
            .clipShape(shape)
            .contentShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// A running entry's block stays open at the bottom, where it grows.
    private var shape: UnevenRoundedRectangle {
        let bottom: CGFloat = entry.isRunning ? 0 : 9
        return UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: 9)
    }

    private var fill: Color {
        if unassigned { return Theme.fill }
        return selected || entry.isRunning ? tint.strongFill : tint.fill
    }

    @ViewBuilder
    private var border: some View {
        if selected {
            shape.strokeBorder(Theme.selection, lineWidth: 2)
        } else if change != nil {
            shape.strokeBorder(Theme.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        } else if unassigned {
            shape.strokeBorder(Theme.ghost, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(tint.ink, lineWidth: 1)
        }
    }

    private var title: String {
        entry.entry.note.isEmpty ? model.ledger.projectTitle(entry.entry.projectID) : entry.entry.note
    }

    private var project: String? {
        guard !entry.entry.note.isEmpty, let projectID = entry.entry.projectID else { return nil }
        return model.ledger.projects[projectID]?.name
    }

    @ViewBuilder
    private var content: some View {
        if height < 34 {
            HStack(spacing: 7) {
                Text(Format.time(entry.start, zone: zone))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text4)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                if entry.isRunning {
                    Text(Format.duration(model.duration(of: entry)))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if entry.isRunning {
                    HStack(spacing: 8) {
                        Text(title).fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Text(Format.duration(model.duration(of: entry)))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                } else {
                    times
                    HStack(spacing: 5) {
                        Text(title).fontWeight(.semibold)
                        if let project {
                            Text("· \(project)").foregroundStyle(Theme.text2)
                        }
                    }
                    .font(.system(size: 13.5))
                    .lineLimit(height > 64 ? 2 : 1)
                }
                if !entry.entry.tags.isEmpty, height > 44 {
                    Text(entry.entry.tags.joined(separator: " "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tag)
                        .lineLimit(1)
                }
                if let overnight, height > 76 {
                    Text(overnight)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.amberText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.amberFill))
                        .padding(.top, 2)
                }
            }
        }
    }

    /// "09:00–12:40", or with a suggestion "09:00–12:40 11:00", the old end
    /// struck through.
    private var times: some View {
        HStack(spacing: 3) {
            if let change {
                let startChanged = change.before.start != change.after.start
                let endChanged = change.before.end != change.after.end
                ChangedText(old: startChanged ? Format.time(change.before.start, zone: zone) : nil, new: Format.time(change.after.start, zone: zone), size: 11.5)
                Text("–")
                ChangedText(
                    old: endChanged ? change.before.end.map { Format.time($0, zone: zone) } ?? "now" : nil,
                    new: change.after.end.map { Format.time($0, zone: zone) } ?? "now",
                    size: 11.5
                )
            } else {
                Text("\(Format.time(entry.start, zone: zone))–\(entry.end.map { Format.time($0, zone: zone) } ?? "now")")
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .foregroundStyle(Theme.text4)
        .lineLimit(1)
    }
}

/// What an entry's menu offers, on a long press.
struct PhoneEntryMenu: View {
    let model: AppModel
    let entry: ResolvedEntry
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if entry.isRunning {
            Button("Stop", systemImage: "stop.fill") {
                model.stopTimer(undoManager: undoManager)
            }
        } else {
            Button("Continue", systemImage: "play.fill") {
                model.startTimer(Combination(projectID: entry.entry.projectID, tags: entry.entry.tags), note: entry.entry.note, undoManager: undoManager)
            }
        }
        Menu("Project") {
            ForEach(model.ledger.pickerProjects()) { project in
                Button(model.ledger.projectTitle(project.id)) {
                    model.updateEntries([entry.id], actionName: "Set Project", undoManager: undoManager) { $0.projectID = project.id }
                }
            }
            Divider()
            Button("Unassigned") {
                model.updateEntries([entry.id], actionName: "Set Project", undoManager: undoManager) { $0.projectID = nil }
            }
        }
        if EntrySplit.range(of: entry, now: model.now) != nil {
            Button("Split in the Middle", systemImage: "scissors") {
                model.splitEntry(entry.id, at: Timestamp(EntrySplit.suggestedTime(for: entry, now: model.now)), undoManager: undoManager)
            }
        }
        if !entry.isRunning {
            Button("Duplicate", systemImage: "plus.square.on.square") {
                model.duplicateEntries([entry.id], undoManager: undoManager)
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.deleteEntries([entry.id], undoManager: undoManager)
        }
    }
}
#endif

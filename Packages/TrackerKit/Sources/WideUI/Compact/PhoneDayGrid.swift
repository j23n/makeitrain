import SwiftUI
import TrackerCore
import TrackerKit

/// One day on an hour grid, as the narrow layout's Week shows it: the
/// hours down the side, with the current time on today, and the day's
/// column, the same as each of the week's in the wide layout, at the
/// narrow layout's size (`DayColumn`, `DayGridMetrics.compact`): the
/// entries as blocks, what the corrections would change drawn over them,
/// and a new entry being drawn.
struct PhoneDayGrid: View {
    let model: AppModel
    let week: WeekModel
    let day: LocalDate
    var gutter: CGFloat = 52
    let onSelect: (ResolvedEntry) -> Void

    private let hourHeight = DayGridMetrics.compact.hourHeight
    private var zone: String { model.environment.timeZone() }

    var body: some View {
        let blocks = DayLayout.blocks(on: day, entries: week.entries(on: day), now: model.now)
        let hours = DayLayout.hours(
            blocks: blocks,
            additions: week.suggestedAdditions.map(\.entry).filter { $0.day == day },
            nowHour: day == model.today ? model.now.local(in: zone).hour : nil
        )
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            Color.clear.frame(height: hourHeight).id(hour)
                        }
                    }
                    gutterLabels(hours)
                    DayColumn(
                        model: model,
                        week: week,
                        days: [day],
                        index: 0,
                        blocks: blocks,
                        hours: hours,
                        metrics: .compact,
                        isShown: { _ in true },
                        onSelect: { entry in
                            if let entry {
                                onSelect(entry)
                            }
                        }
                    )
                    .frame(height: CGFloat(hours.count) * hourHeight)
                    .padding(.leading, gutter)
                    .padding(.trailing, 16)
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

    private func y(_ second: Int, _ hours: Range<Int>) -> CGFloat {
        (CGFloat(second) / 3600 - CGFloat(hours.lowerBound)) * hourHeight
    }

    private func y(_ time: Timestamp, zone: String, _ hours: Range<Int>) -> CGFloat {
        y(DayLayout.second(of: time, on: day, zone: zone), hours)
    }

    /// The hours down the side, and the current time on today.
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
}

/// One entry on the iPhone's grid: its times, tags and title in its
/// project's tint, outlined when selected, dashed amber when a suggestion
/// would change it. As on the week, the tags come before the title, which
/// gets what's left of a one-line block, and a block too short for a line
/// is a bar.
struct PhoneEntryBlock: View {
    let model: AppModel
    let entry: ResolvedEntry
    let height: CGFloat
    let selected: Bool
    let change: (before: TimeEntry, after: TimeEntry)?
    let overnight: String?
    /// Whether it overlaps another entry, so it keeps an amber edge.
    var overlaps = false

    private var unassigned: Bool { entry.entry.projectID == nil }
    private var tint: ProjectTint { model.ledger.tint(ofProject: entry.entry.projectID) }
    private var zone: String { entry.entry.timeZone }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, height < 34 ? 0 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height < 34 ? .leading : .topLeading)
            .entryBlockChrome(shape, tint: tint, unassigned: unassigned, selected: selected, running: entry.isRunning, changed: change != nil, overlaps: overlaps)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summary))
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// A running entry's block stays open at the bottom, where it grows.
    private var shape: UnevenRoundedRectangle {
        let radius = min(9, height / 2)
        let bottom: CGFloat = entry.isRunning ? 0 : radius
        return UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: radius)
    }

    private var title: String {
        model.ledger.title(of: entry.entry)
    }

    private var tags: String {
        entry.entry.tags.joined(separator: " ")
    }

    /// The block's times, tags and title, and how long it ran overnight,
    /// for VoiceOver.
    private var summary: String {
        [Format.span(entry.start, entry.end, zone: zone), tags, title, overnight ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var project: String? {
        guard !entry.entry.note.isEmpty, let projectID = entry.entry.projectID else { return nil }
        return model.ledger.projects[projectID]?.name
    }

    @ViewBuilder
    private var content: some View {
        if height < 13 {
            // Too short for a line of text: a bar. Not an EmptyView,
            // which would take the block's fill away with it.
            Color.clear
        } else if height < 34 {
            HStack(spacing: 7) {
                Text(Format.time(entry.start, zone: zone))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text4)
                    .layoutPriority(2)
                if !tags.isEmpty {
                    tagsText
                        .layoutPriority(1)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                if entry.isRunning {
                    Text(Format.duration(model.duration(of: entry)))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .layoutPriority(2)
                }
            }
            .lineLimit(1)
        } else {
            let hasTags = !tags.isEmpty
            VStack(alignment: .leading, spacing: 2) {
                if entry.isRunning {
                    HStack(spacing: 8) {
                        if hasTags {
                            tagsText
                                .layoutPriority(1)
                        }
                        Text(title).fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Text(Format.duration(model.duration(of: entry)))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .layoutPriority(2)
                    }
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                } else {
                    times
                    if hasTags {
                        tagsText
                    }
                    // Under the tags, the title needs a third line.
                    if !hasTags || height >= 54 {
                        HStack(spacing: 5) {
                            Text(title).fontWeight(.semibold)
                            if let project {
                                Text("· \(project)").foregroundStyle(Theme.text2)
                            }
                        }
                        .font(.system(size: 13.5))
                        .lineLimit(height > (hasTags ? 82 : 64) ? 2 : 1)
                    }
                }
                if let overnight, height > (hasTags && !entry.isRunning ? 94 : 76) {
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

    private var tagsText: some View {
        Text(tags)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.tag)
            .lineLimit(1)
    }

    /// "09:00–12:40", or with a suggestion "09:00–12:40 11:00", the old end
    /// struck through.
    private var times: some View {
        HStack(spacing: 3) {
            if let change {
                ChangedSpan(before: change.before, after: change.after, zone: zone, size: 11.5)
            } else {
                Text(Format.span(entry.start, entry.end, zone: zone))
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .foregroundStyle(Theme.text4)
        .lineLimit(1)
    }
}

import SwiftUI
import TrackerCore
import TrackerKit

/// A project's last twelve weeks, a row of days each, with each day's time
/// as a bar and the week's total, on its page. In the narrow layout the
/// rows are shorter, without the weekdays over them, and the panel around
/// them is left to the page.
struct ProjectWeeks: View {
    let model: AppModel
    let projectID: UUID
    let tint: ProjectTint
    let compact: Bool
    let openMonth: () -> Void

    init(model: AppModel, projectID: UUID, tint: ProjectTint, compact: Bool = false, openMonth: @escaping () -> Void) {
        self.model = model
        self.projectID = projectID
        self.tint = tint
        self.compact = compact
        self.openMonth = openMonth
    }

    private var labelWidth: CGFloat { compact ? 44 : 52 }
    private var totalWidth: CGFloat { compact ? 64 : 72 }

    var body: some View {
        let today = model.today
        let thisWeek = ReportPeriod.week.range(containing: today, firstWeekday: model.firstWeekday)
        let first = thisWeek.lowerBound.adding(days: -77)
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            header
            if !compact {
                HStack(spacing: 4) {
                    Text("").frame(width: labelWidth)
                    ForEach(0..<7, id: \.self) { offset in
                        Text(Format.weekday(thisWeek.lowerBound.adding(days: offset)).prefix(1))
                            .frame(maxWidth: .infinity)
                    }
                    Text("Week").frame(width: totalWidth, alignment: .trailing)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
            }
            VStack(spacing: compact ? 3 : 10) {
                ForEach(0..<12, id: \.self) { index in
                    row(index: index, start: first.adding(days: index * 7), today: today)
                }
            }
        }
        .padding(compact ? 0 : 16)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 12).fill(Theme.panel)
            }
        }
        .overlay {
            if !compact {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if compact {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 12 weeks")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Open in Month", action: openMonth)
                    .font(.system(size: 13.5))
            }
            .padding(.horizontal, 2)
        } else {
            HStack {
                Text("Last 12 weeks").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.amber).frame(width: 8, height: 8)
                    Text("over 12 hours")
                }
                Button("Open in Month ›", action: openMonth)
                    .linkButton()
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
        }
    }

    /// The week starting on `start`: its date, a cell a day and its total.
    private func row(index: Int, start: LocalDate, today: LocalDate) -> some View {
        let days = (0..<7).map { start.adding(days: $0) }
        let times = days.map { model.dayTotals.projects(on: $0, now: model.now)[projectID] ?? 0 }
        let total = times.reduce(0, +)
        return HStack(spacing: 4) {
            Text(Format.monthDay(start))
                .foregroundStyle(index == 11 ? Theme.text : Theme.text3)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            ForEach(0..<7, id: \.self) { offset in
                let day = days[offset]
                let time = times[offset]
                ProjectDayCell(
                    day: day,
                    time: time,
                    today: today,
                    tint: tint,
                    barHeight: compact ? 13 : 20,
                    sideInset: compact ? 2 : 5,
                    bottomInset: compact ? 2 : 3
                )
                .frame(height: compact ? nil : 26)
                .help("\(Format.longDay(day)), \(time > 0 ? Format.duration(time) : "no time")")
            }
            Text(total > 0 ? Format.duration(total) : "—")
                .monospacedDigit()
                .foregroundStyle(total > ChartScale.longWeek ? Theme.amberText : (total > 0 ? Theme.text : Theme.text3))
                .lineLimit(1)
                .frame(width: totalWidth, alignment: .trailing)
        }
        .font(.system(size: 11.5))
        .frame(height: compact ? 17 : nil)
        .accessibilityElement(children: compact ? .ignore : .contain)
        .accessibilityLabel(Text("Week of \(Format.monthDay(start)), \(total > 0 ? Format.duration(total) : "no time")"))
    }
}

#if DEBUG
#Preview("Wide") {
    let model = PreviewData.model()
    return ProjectWeeks(model: model, projectID: model.ledger.pickerProjects()[0].id, tint: ProjectTint(hex: model.ledger.pickerProjects()[0].color)) {}
        .padding()
        .frame(width: 640)
}

#Preview("Narrow") {
    let model = PreviewData.model()
    return ProjectWeeks(model: model, projectID: model.ledger.pickerProjects()[0].id, tint: ProjectTint(hex: model.ledger.pickerProjects()[0].color), compact: true) {}
        .padding()
        .frame(width: 390)
}
#endif

import SwiftUI
import TrackerCore

// Pieces the projects list and a project's page draw on the Mac, iPhone
// and iPad.

/// Twelve weeks as small bars, this week last, full at 40 hours unless a
/// week is longer.
public struct Sparkline: View {
    let values: [Int64]
    let tint: ProjectTint
    let height: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat

    public init(values: [Int64], tint: ProjectTint, height: CGFloat = 26, spacing: CGFloat = 3, cornerRadius: CGFloat = 2) {
        self.values = values
        self.tint = tint
        self.height = height
        self.spacing = spacing
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let highest = max(values.max() ?? 0, ChartScale.fullWeek)
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(values.indices, id: \.self) { index in
                UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                    .fill(values[index] > 0 ? tint.bar : Theme.emptyBar)
                    .frame(height: values[index] > 0 ? max(2, CGFloat(values[index]) / CGFloat(highest) * height) : 1)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 12 weeks: \(values.map { Format.duration($0) }.joined(separator: ", "))"))
    }
}

/// A day of a project's last twelve weeks: its time as a bar, amber over
/// 12 hours, on a cell outlined for today and dashed for the days to come.
public struct ProjectDayCell: View {
    let day: LocalDate
    let time: Int64
    let today: LocalDate
    let tint: ProjectTint
    let barHeight: CGFloat
    let sideInset: CGFloat
    let bottomInset: CGFloat

    public init(day: LocalDate, time: Int64, today: LocalDate, tint: ProjectTint, barHeight: CGFloat, sideInset: CGFloat, bottomInset: CGFloat) {
        self.day = day
        self.time = time
        self.today = today
        self.tint = tint
        self.barHeight = barHeight
        self.sideInset = sideInset
        self.bottomInset = bottomInset
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(day > today ? Color.clear : (day.weekday == 1 || day.weekday == 7 ? Theme.weekendCell : Theme.cell))
                .overlay {
                    if day > today {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.strongLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    } else if day == today {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1.5)
                    }
                }
            if time > 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(time > Corrections.longest ? Theme.amber : tint.bar)
                    .frame(height: max(2, CGFloat(min(time, ChartScale.fullDay)) / CGFloat(ChartScale.fullDay) * barHeight))
                    .padding(.horizontal, sideInset)
                    .padding(.bottom, bottomInset)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

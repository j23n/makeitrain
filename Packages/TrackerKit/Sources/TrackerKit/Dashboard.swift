import SwiftUI
import TrackerCore

// The parts of pages about where time went, shared by the reports, the
// project pages and the timeline's summary on the Mac and iOS: panels,
// figures with their names, bars for shares, and charts of time.

extension View {
    /// Sets a part of a page apart on a rounded panel, such as a figure, a
    /// chart or a list of times.
    public func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            }
    }
}

/// A figure on a panel, with its name above it and a line about it below,
/// such as a report's total and how many entries make it up. Figures side
/// by side are as tall as the tallest when their row is fixed to its ideal
/// height.
public struct FigureTile<Value: View>: View {
    let title: String
    let detail: String?
    let value: Value

    public init(_ title: String, detail: String? = nil, @ViewBuilder value: () -> Value) {
        self.title = title
        self.detail = detail
        self.value = value()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            value
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // A small ideal width, so a row of figures fits a narrow window
        // before it wraps.
        .frame(minWidth: 0, idealWidth: 110, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// A duration as `Format.duration(_:)` writes it, large and rounded, with
/// the units of a long one smaller than its numbers, as in "574 h 46 m".
public struct DurationText: View {
    let milliseconds: Int64
    @ScaledMetric private var size: CGFloat

    public init(_ milliseconds: Int64, size: CGFloat = 28) {
        self.milliseconds = milliseconds
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    public var body: some View {
        text
            .monospacedDigit()
            .accessibilityLabel(Text(Format.duration(milliseconds)))
    }

    private var text: Text {
        let numbers = Font.system(size: size, weight: .semibold, design: .rounded)
        let units = Font.system(size: (size * 0.6).rounded(), weight: .semibold, design: .rounded)
        var result: Text?
        for part in Format.durationParts(milliseconds) {
            var piece = Text(part.number).font(numbers)
            if let unit = part.unit {
                piece = Text("\(piece)\u{00A0}\(Text(unit).font(units))")
            }
            result = result.map { Text("\($0)\u{00A0}\(piece)") } ?? piece
        }
        return result ?? Text("")
    }
}

/// A figure that isn't a duration, such as a count or a change, set in the
/// numbers' font of `DurationText`.
public struct FigureText: View {
    let text: String
    @ScaledMetric private var size: CGFloat

    public init(_ text: String, size: CGFloat = 28) {
        self.text = text
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

/// A bar for a share of a whole, on a faint track as long as the whole: in
/// one color, or a stretch in each part's color, such as a client's
/// projects. Any share at all is long enough to see.
public struct ShareBar: View {
    /// Some of the bar, such as a project's time.
    public struct Part: Hashable {
        public var color: Color
        public var value: Int64

        public init(color: Color, value: Int64) {
            self.color = color
            self.value = value
        }
    }

    let parts: [Part]
    let whole: Int64
    let height: CGFloat

    public init(_ value: Int64, of whole: Int64, color: Color, height: CGFloat = 6) {
        self.init(parts: [Part(color: color, value: value)], of: whole, height: height)
    }

    public init(parts: [Part], of whole: Int64, height: CGFloat = 6) {
        self.parts = parts
        self.whole = whole
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            let total = parts.reduce(Int64(0)) { $0 + max($1.value, 0) }
            let width = geometry.size.width
            let length = whole > 0 && total > 0
                ? max(width * min(CGFloat(total) / CGFloat(whole), 1), min(height, width))
                : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                if length > 0 {
                    HStack(spacing: 0) {
                        ForEach(parts.indices, id: \.self) { index in
                            Rectangle()
                                .fill(parts[index].color)
                                .frame(width: length * CGFloat(max(parts[index].value, 0)) / CGFloat(total))
                        }
                    }
                    .frame(width: length, alignment: .leading)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A day, a week or a month in a bar chart, with its time in parts, such as
/// a part for each project.
public struct ChartColumn: Identifiable, Hashable {
    /// Some of a column's time, such as a project's, or a part of a chart's
    /// legend.
    public struct Part: Identifiable, Hashable {
        public var id: String
        public var title: String
        public var color: Color
        public var milliseconds: Int64

        public init(id: String, title: String, color: Color, milliseconds: Int64) {
            self.id = id
            self.title = title
            self.color = color
            self.milliseconds = milliseconds
        }
    }

    public var id: String
    /// Under the bar, such as "Mon", "28" or "Sep 7".
    public var label: String
    /// The days it covers, for its tooltip and VoiceOver, such as
    /// "Mon, Sep 28".
    public var title: String
    /// From the bottom up.
    public var parts: [Part]
    /// Whether it's today's, or this week's or month's, whose label stands
    /// out.
    public var isCurrent: Bool

    public init(id: String, label: String, title: String, parts: [Part], isCurrent: Bool = false) {
        self.id = id
        self.label = label
        self.title = title
        self.parts = parts
        self.isCurrent = isCurrent
    }

    /// The time of all its parts.
    public var milliseconds: Int64 {
        parts.reduce(0) { $0 + $1.milliseconds }
    }
}

/// Time as columns, each stacked by its parts in their colors, with its
/// total over it and its label under it. Totals show when the columns are
/// wide enough for them, and labels as often as they fit. A dashed line
/// marks an average when there is one.
public struct BarChart: View {
    let columns: [ChartColumn]
    let average: Int64?
    let height: CGFloat

    private static let totalHeight: CGFloat = 16
    private static let labelHeight: CGFloat = 18

    /// `height` is the tallest bar's.
    public init(columns: [ChartColumn], average: Int64? = nil, height: CGFloat = 160) {
        self.columns = columns
        self.average = average
        self.height = height
    }

    public var body: some View {
        let tallest = columns.map(\.milliseconds).max() ?? 0
        let maximum = max(tallest, average ?? 0, 1)
        // The widest total, at about six points a character in the
        // caption's monospaced digits.
        let totalWidth = CGFloat(Format.duration(tallest).count) * 6 + 4
        GeometryReader { geometry in
            let count = max(columns.count, 1)
            let spacing: CGFloat = count > 16 ? 3 : 8
            let width = max((geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)
            // Every label where they fit, or every second, third and so on.
            let every = max(1, Int((30 / (width + spacing)).rounded(.up)))
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(columns) { column in
                        bar(column, width: width, maximum: maximum, showsTotal: width >= totalWidth)
                    }
                }
                .frame(height: height + Self.totalHeight, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    if let average, average > 0 {
                        DashedLine()
                            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(height: 1)
                            .offset(y: -height * CGFloat(average) / CGFloat(maximum))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
                HStack(spacing: spacing) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        Text(index % every == 0 ? column.label : "")
                            .font(.caption2)
                            .fontWeight(column.isCurrent ? .semibold : .regular)
                            .foregroundStyle(column.isCurrent ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: width)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: Self.labelHeight, alignment: .bottom)
            }
        }
        .frame(height: height + Self.totalHeight + 1 + Self.labelHeight)
    }

    /// A column's bar, its parts stacked from the bottom, and its total.
    private func bar(_ column: ChartColumn, width: CGFloat, maximum: Int64, showsTotal: Bool) -> some View {
        let total = column.milliseconds
        return VStack(spacing: 2) {
            if showsTotal, total > 0 {
                Text(Format.duration(total))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            VStack(spacing: 0) {
                ForEach(Array(column.parts.reversed())) { part in
                    Rectangle()
                        .fill(part.color)
                        .frame(height: height * CGFloat(part.milliseconds) / CGFloat(maximum))
                }
            }
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: min(4, width / 3), style: .continuous))
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .help(tooltip(column))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(column.title))
        .accessibilityValue(Text(Format.duration(total)))
    }

    /// The column's days and total, and each part's time.
    private func tooltip(_ column: ChartColumn) -> String {
        let lines = column.parts.count > 1
            ? column.parts.map { "\($0.title): \(Format.duration($0.milliseconds))" }
            : []
        return ([column.title + ": " + Format.duration(column.milliseconds)] + lines).joined(separator: "\n")
    }
}

/// A line across the middle of its frame, to stroke dashed.
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The parts of a chart's columns, such as its projects, each with its
/// color.
public struct ChartLegend: View {
    let parts: [ChartColumn.Part]

    public init(parts: [ChartColumn.Part]) {
        self.parts = parts
    }

    public var body: some View {
        FlowLayout(spacing: 12) {
            ForEach(parts) { part in
                HStack(spacing: 5) {
                    Circle()
                        .fill(part.color)
                        .frame(width: 8, height: 8)
                    Text(part.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Figures") {
    VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
            FigureTile("Total", detail: "31 entries") {
                DurationText(153_060_000, size: 30)
            }
            FigureTile("All Time", detail: "Since June 15") {
                DurationText(2_069_160_000)
            }
            FigureTile("Days Worked", detail: "Out of 7") {
                FigureText("5")
            }
            FigureTile("vs. Previous Week", detail: "37 h 55 m in Sep 14 – 20, 2026") {
                FigureText("+12%")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        ShareBar(40 * 3_600_000, of: 42 * 3_600_000, color: Color(hex: "#4F7CAC"))
        ShareBar(parts: [
            ShareBar.Part(color: Color(hex: "#4F7CAC"), value: 5),
            ShareBar.Part(color: Color(hex: "#C0504D"), value: 3),
        ], of: 20)
        ShareBar(1, of: 1000, color: .accentColor)
    }
    .padding()
    .frame(width: 720)
}

#Preview("Bar Chart") {
    let blue = Color(hex: "#4F7CAC")
    let green = Color(hex: "#9BBB59")
    let hour: Int64 = 3_600_000
    let days = [("Mon", 8, 1), ("Tue", 9, 0), ("Wed", 7, 0), ("Thu", 9, 0), ("Fri", 5, 1), ("Sat", 0, 0), ("Sun", 0, 0)]
    let columns = days.enumerated().map { index, day in
        ChartColumn(
            id: "\(index)",
            label: day.0,
            title: day.0,
            parts: [
                ChartColumn.Part(id: "q", title: "Bookings", color: blue, milliseconds: Int64(day.1) * hour),
                ChartColumn.Part(id: "f", title: "Harbor", color: green, milliseconds: Int64(day.2) * hour),
            ],
            isCurrent: index == 2
        )
    }
    return VStack(alignment: .leading, spacing: 10) {
        BarChart(columns: columns, average: 8 * hour)
        ChartLegend(parts: [
            ChartColumn.Part(id: "q", title: "Northbridge › Bookings", color: blue, milliseconds: 0),
            ChartColumn.Part(id: "f", title: "Zenith › Harbor", color: green, milliseconds: 0),
        ])
    }
    .card()
    .padding()
    .frame(width: 640)
}
#endif

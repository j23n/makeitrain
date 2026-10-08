import SwiftUI
import TrackerCore

// Pieces the month and year reports share on the Mac, iPhone and iPad,
// some of them with the projects' pages.

/// A value as a bar on a track as long as the highest value, as for the
/// lines of a breakdown.
public struct ShareBar: View {
    let value: Int64
    let highest: Int64
    let color: Color
    let height: CGFloat

    public init(_ value: Int64, of highest: Int64, color: Color, height: CGFloat) {
        self.value = value
        self.highest = highest
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(value) / CGFloat(max(highest, 1)))
            }
        }
        .frame(height: height)
    }
}

/// The mark for time counted twice, as on a day whose entries overlap:
/// stripes in an amber outline, `size` points square.
public struct OverlapSwatch: View {
    let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let corner: CGFloat = size >= 12 ? 3 : 2
        Hatching()
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.amber))
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

/// The time at which the charts' bars are full, in milliseconds.
public enum ChartScale {
    /// A day's bar, at 10½ hours.
    public static let fullDay: Int64 = 10 * 3_600_000 + 30 * 60_000
    /// A week's bar, at 40 hours unless a week shown is longer.
    public static let fullWeek: Int64 = 40 * 3_600_000
    /// A week longer than 50 hours is marked as long.
    public static let longWeek: Int64 = 50 * 3_600_000
}

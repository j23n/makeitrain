import Observation
import SwiftUI
import TrackerKit

/// A window of the app, on the Mac, an iPhone or an iPad, laid out for its
/// width: the wide layout, with the bar and the week's seven days, from
/// `wideWidth` points, and the narrow one, with tabs and one day at a time,
/// below it. The layout follows the window as it's resized, so each window
/// picks its own, and the window's place, a `WindowPlace`, carries over to
/// the layout it changes to.
public struct AdaptiveRoot<Wide: View, Narrow: View>: View {
    /// The width from which a window uses the wide layout.
    public static var wideWidth: CGFloat { 960 }

    let wide: Wide
    let narrow: Narrow
    @State private var place = WindowPlace()

    public init(@ViewBuilder wide: () -> Wide, @ViewBuilder narrow: () -> Narrow) {
        self.wide = wide()
        self.narrow = narrow()
    }

    /// Whether a window `width` points wide uses the wide layout.
    public static func isWide(_ width: CGFloat) -> Bool {
        width >= wideWidth
    }

    public var body: some View {
        GeometryReader { geometry in
            if Self.isWide(geometry.size.width) {
                wide
            } else {
                narrow
            }
        }
        .environment(place)
    }
}

/// Where a window is, which both of its layouts keep up to date, so the one
/// it changes to as it's resized opens there instead of on today. It's the
/// wide layout's screen; the narrow layout shows it on its tabs as
/// `CompactRouter.show(_:today:firstWeekday:)` describes.
@MainActor
@Observable
final class WindowPlace {
    /// The screen the window shows, or nil before either layout appeared.
    var screen: Screen?
}

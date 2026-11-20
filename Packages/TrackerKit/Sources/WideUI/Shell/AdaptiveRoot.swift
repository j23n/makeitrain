import SwiftUI
import TrackerKit

/// A window of the app, on the Mac, an iPhone or an iPad, laid out for its
/// width: the wide layout, with the bar and the week's seven days, from
/// `wideWidth` points, and the narrow one, with tabs and one day at a time,
/// below it. The layout follows the window as it's resized, so each window
/// picks its own.
public struct AdaptiveRoot<Wide: View, Narrow: View>: View {
    /// The width from which a window uses the wide layout.
    public static var wideWidth: CGFloat { 960 }

    let wide: Wide
    let narrow: Narrow

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
    }
}

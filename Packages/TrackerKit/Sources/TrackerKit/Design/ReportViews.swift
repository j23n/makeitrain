import SwiftUI
import TrackerCore

// Pieces the month and year reports share on the Mac, iPhone and iPad.

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

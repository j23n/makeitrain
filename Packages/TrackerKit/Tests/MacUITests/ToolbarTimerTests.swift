#if os(macOS)
import Foundation
import Testing
@testable import MacUI

@Suite struct ToolbarTimerTests {
    @Test func movesToTheMiddleOfTheSpaceBetweenTheTitleAndTheItems() {
        // The toolbar centers the item at 505, but the title ends at 75 and
        // the first button starts at 860, so the middle of the space is 467.5.
        #expect(ToolbarTimer.shift(itemCenter: 505, width: 262, left: 75, right: 860) == -38)
        // A long title on the other side moves it the other way.
        #expect(ToolbarTimer.shift(itemCenter: 505, width: 262, left: 250, right: 960) == 100)
    }

    @Test func movesOnlyAsFarAsTheWidenedItemStaysClear() {
        #expect(ToolbarTimer.shift(itemCenter: 505, width: 600, left: 75, right: 860) == -38)
        // A 680-point item centered on 505 reaches 845. Moved 7 points to the
        // left, it's 14 points wider and reaches 852, 8 short of the button.
        #expect(ToolbarTimer.shift(itemCenter: 505, width: 680, left: 75, right: 860) == -7)
        #expect(ToolbarTimer.shift(itemCenter: 505, width: 800, left: 75, right: 860) == 0)
    }

    @Test func staysPutWhenAlreadyInTheMiddle() {
        #expect(ToolbarTimer.shift(itemCenter: 500, width: 200, left: 100, right: 900) == 0)
    }
}
#endif

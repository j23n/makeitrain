#if os(macOS)
import Foundation
import Testing
@testable import MacUI

@Suite struct ToolbarTimerTests {
    /// Centers a timer `width` wide in `space`, in a toolbar that puts its
    /// middle at `place(padding)`, until the centering stops changing the
    /// padding. Where the timer ends up, and how many changes that took.
    func settle(width: CGFloat, space: ClosedRange<CGFloat>, place: (CGFloat) -> CGFloat) -> (center: CGFloat, changes: Int) {
        var centering = TimerCentering()
        var center = place(0)
        var changes = 0
        while let padding = centering.update(center: center, width: width, space: space), changes < 20 {
            changes += 1
            center = place(padding)
        }
        return (center, changes)
    }

    @Test func centersAnItemTheToolbarCenters() {
        // The toolbar centers the item on 505; padding on one side widens it
        // on both, so the timer moves half as far.
        let result = settle(width: 262, space: 75...860) { padding in 505 + padding / 2 }
        #expect(abs(result.center - 467.5) <= 1)
        #expect(result.changes == 1)
    }

    @Test func centersAnItemRightAfterTheTitle() {
        // Without room to center it, the toolbar puts the item right after
        // the title, at 290, and leading padding moves the timer as far.
        let result = settle(width: 411, space: 206...816) { padding in 290 + 411 / 2 + max(0, padding) }
        #expect(abs(result.center - 511) <= 1)
        #expect(result.changes <= 3)
    }

    @Test func centersAnItemAgainstTheButtons() {
        // An item that ends against the buttons moves left with trailing
        // padding, as far.
        let result = settle(width: 411, space: 281...883) { padding in 875 - 411 / 2 + min(0, padding) }
        #expect(abs(result.center - 582) <= 1)
        #expect(result.changes <= 3)
    }

    @Test func staysPutInTheMiddle() {
        var centering = TimerCentering()
        #expect(centering.update(center: 500, width: 200, space: 100...900) == nil)
    }

    @Test func stopsAfterEightChanges() {
        // A toolbar that moves the timer somewhere else each time.
        var centering = TimerCentering()
        var changes = 0
        var center: CGFloat = 505
        while centering.update(center: center, width: 262, space: 75...860) != nil, changes < 20 {
            changes += 1
            center = changes.isMultiple(of: 2) ? 300 : 700
        }
        #expect(changes == 8)
    }

    @Test func dropsThePaddingWithNothingToCenterIn() {
        var centering = TimerCentering()
        #expect(centering.update(center: 505, width: 262, space: 75...860) == -75)
        #expect(centering.update(center: 467, width: 262, space: nil) == 0)
        #expect(centering.update(center: 505, width: 262, space: nil) == nil)
    }
}
#endif

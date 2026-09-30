#if os(macOS)
import Foundation
import Testing
@testable import MacUI

@Suite struct ToolbarTimerTests {
    @Test func movesOverTheMiddleOfTheDetailColumn() {
        // A 1,200-point window with a 200-point sidebar. The toolbar centers
        // the item at 600; 200 points of padding move its content to 700.
        let detail = CGRect(x: 200, y: 0, width: 1000, height: 600)
        #expect(ToolbarTimer.leadingPadding(detail: detail, width: 260, titleSpace: 150) == 200)
    }

    @Test func leavesTheTitleRoom() {
        // In an 880-point window, the item has to stay right of 180 + 150.
        let detail = CGRect(x: 180, y: 0, width: 700, height: 600)
        #expect(ToolbarTimer.leadingPadding(detail: detail, width: 200, titleSpace: 150) == 20)
        #expect(ToolbarTimer.leadingPadding(detail: detail, width: 300, titleSpace: 150) == 0)
    }

    @Test func staysInTheMiddleWithoutASidebar() {
        let detail = CGRect(x: 0, y: 0, width: 1200, height: 600)
        #expect(ToolbarTimer.leadingPadding(detail: detail, width: 260, titleSpace: 150) == 0)
        // Before the first layout, nothing is known yet.
        #expect(ToolbarTimer.leadingPadding(detail: .zero, width: 0, titleSpace: 150) == 0)
    }

    @Test func makesRoomForTheLongestTitle() {
        #expect(ToolbarTimer.titleSpace > 100)
        #expect(ToolbarTimer.titleSpace < 300)
    }
}
#endif

import CoreGraphics
import Testing
@testable import AdaptiveUI

@Suite struct ProjectColumnTests {
    @Test func theTableIsAtLeastAsWideAsItsColumns() {
        #expect(ProjectColumn.tableWidth == 1358)
    }

    @Test func aWideViewStretchesTheTable() {
        #expect(ProjectColumn.layoutWidth(in: 1600) == 1600)
        #expect(ProjectColumn.layoutWidth(in: 1358) == 1358)
    }

    /// A new window, with 24 points on each side of the table, leaves room
    /// for every column.
    @Test func aNewWindowIsWideEnoughForEveryColumn() {
        #expect(ProjectColumn.tableWidth <= WideWindow.defaultWidth - 48)
    }

    /// The wide layout is at least 960 points wide, with 24 on each side
    /// of the table: there the table keeps its least width and scrolls.
    @Test func aNarrowViewKeepsTheTablesLeastWidth() {
        #expect(ProjectColumn.layoutWidth(in: 912) == 1358)
        #expect(ProjectColumn.layoutWidth(in: 0) == 1358)
    }
}

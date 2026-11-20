import CoreGraphics
import Testing
@testable import WideUI

@Suite struct ProjectColumnTests {
    @Test func theTableIsAtLeastAsWideAsItsColumns() {
        #expect(ProjectColumn.tableWidth == 1358)
    }

    @Test func aWideViewStretchesTheTable() {
        #expect(ProjectColumn.layoutWidth(in: 1600) == 1600)
        #expect(ProjectColumn.layoutWidth(in: 1358) == 1358)
    }

    /// The main window opens 1410 points wide, with 24 on each side of the
    /// table, which leaves room for every column.
    @Test func theMainWindowOpensWideEnoughForEveryColumn() {
        #expect(ProjectColumn.layoutWidth(in: 1410 - 48) == 1410 - 48)
    }

    /// The main window is at least 960 points wide, with 24 on each side
    /// of the table: there the table keeps its least width and scrolls.
    @Test func aNarrowViewKeepsTheTablesLeastWidth() {
        #expect(ProjectColumn.layoutWidth(in: 912) == 1358)
        #expect(ProjectColumn.layoutWidth(in: 0) == 1358)
    }
}

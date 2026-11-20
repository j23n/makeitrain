import CoreGraphics
import Testing
@testable import WideUI

@Suite struct ProjectColumnTests {
    @Test func aWideTableShowsEveryColumn() {
        let all = Set(ProjectColumn.allCases)
        #expect(ProjectColumn.minimumWidth(of: all) == 1358)
        #expect(ProjectColumn.fitting(1358) == all)
        #expect(ProjectColumn.fitting(2000) == all)
    }

    @Test func aNarrowingTableLeavesColumnsOutInOrder() {
        #expect(ProjectColumn.fitting(1357) == [.name, .repositories, .calendar, .contract, .week, .month, .total])
        #expect(ProjectColumn.fitting(1185) == [.name, .repositories, .contract, .week, .month, .total])
        #expect(ProjectColumn.fitting(999) == [.name, .contract, .week, .month, .total])
        #expect(ProjectColumn.fitting(833) == [.name, .contract, .week, .month])
        #expect(ProjectColumn.fitting(713) == [.name, .week, .month])
    }

    @Test func theNameAndTimesAlwaysShow() {
        #expect(ProjectColumn.fitting(0) == [.name, .week, .month])
    }

    /// The main window is at least 960 points wide, with 24 on each side
    /// of the table, and opens 1320 wide.
    @Test func theTableFitsTheMainWindow() {
        for windowWidth: CGFloat in [960, 1100, 1320, 1600] {
            let width = windowWidth - 48
            #expect(ProjectColumn.minimumWidth(of: ProjectColumn.fitting(width)) <= width)
        }
        #expect(ProjectColumn.fitting(912) == [.name, .contract, .week, .month, .total])
    }
}

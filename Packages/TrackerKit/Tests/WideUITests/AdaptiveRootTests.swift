import SwiftUI
import Testing
@testable import WideUI

/// Which layout a window gets for its width.
@Suite struct AdaptiveRootTests {
    typealias Root = AdaptiveRoot<EmptyView, EmptyView>

    @Test func usesTheWideLayoutFromNineHundredSixtyPoints() {
        #expect(Root.isWide(960))
        #expect(Root.isWide(1320))
    }

    @Test func usesTheNarrowLayoutBelowIt() {
        #expect(!Root.isWide(959))
        // An iPhone in landscape, and the Mac's narrowest main window.
        #expect(!Root.isWide(932))
        #expect(!Root.isWide(360))
    }
}

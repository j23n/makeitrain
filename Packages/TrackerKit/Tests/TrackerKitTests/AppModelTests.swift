import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct AppModelTests {
    @Test @MainActor func startsEmpty() {
        #expect(AppModel().ledger == Ledger())
    }
}

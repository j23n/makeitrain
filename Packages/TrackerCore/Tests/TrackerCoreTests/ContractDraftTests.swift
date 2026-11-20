import Foundation
import Testing
@testable import TrackerCore

@Suite struct ContractDraftTests {
    let contract = Contract(
        id: uuid(1),
        hours: 120,
        start: LocalDate(year: 2026, month: 9, day: 1),
        end: LocalDate(year: 2026, month: 12, day: 31)
    )

    @Test func hoursThatArentANumberAreInvalid() {
        var draft = ContractDraft(contract)
        draft.hoursText = "abc"
        #expect(draft.hours == 0)
        #expect(!draft.contract.isValid)
        draft.hoursText = " 80 "
        #expect(draft.contract.hours == 80)
        #expect(draft.contract.isValid)
    }

    @Test func anAlertAboveTheHoursIsLoweredToThem() {
        var draft = ContractDraft(contract)
        draft.alertHours = 50
        draft.hoursText = "20"
        #expect(draft.contract.alertHours == 20)
        #expect(draft.alertHours == 20)
    }

    @Test func turningTheAlertOffKeepsZeroAndOnGoesBackToTheDefault() {
        var draft = ContractDraft(contract)
        draft.alertHours = 30
        draft.alerts = false
        #expect(draft.contract.alertHours == 0)
        #expect(!draft.alerts)
        draft.alerts = true
        #expect(draft.contract.alertHours == nil)
        #expect(draft.alertHours == 12)
    }

    @Test func steppingToTheDefaultKeepsNil() {
        var draft = ContractDraft(contract)
        draft.alertHours = 13
        #expect(draft.contract.alertHours == 13)
        draft.alertHours = 12
        #expect(draft.contract.alertHours == nil)
        draft.hoursText = "40"
        #expect(draft.alertHours == 4)
    }

    @Test func anUnchangedDraftIsTheContract() {
        #expect(ContractDraft(contract).contract == contract)
    }
}

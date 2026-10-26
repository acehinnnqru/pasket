import AppKit
import Carbon
import Testing
@testable import PasketCore

struct AppLaunchTests {
    @Test func loginItemLaunchIsRecognized() {
        let event = launchEvent()
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)

        #expect(AppLaunch.isLoginItemLaunch(event))
    }

    @Test func manualLaunchesDoNotSuppressHistory() {
        #expect(!AppLaunch.isLoginItemLaunch(nil))
        #expect(!AppLaunch.isLoginItemLaunch(launchEvent()))
        let event = launchEvent()
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsServiceItem), forKeyword: keyAEPropData)
        #expect(!AppLaunch.isLoginItemLaunch(event))
    }

    @Test func reopenEventsAreNotLoginLaunches() {
        let event = launchEvent(eventID: kAEReopenApplication)
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)

        #expect(!AppLaunch.isLoginItemLaunch(event))
    }

    private func launchEvent(eventID: AEEventID = kAEOpenApplication) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: eventID, targetDescriptor: nil,
                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }
}

import Foundation
import ServiceManagement
import Testing
@testable import PasketCore

@MainActor
struct LoginItemPreferencesTests {
    @Test func changesRegisterAndUnregisterTheLoginItem() {
        let service = TestLoginItemService()
        let preferences = LoginItemPreferences(service: service)

        #expect(!preferences.isEnabled)
        #expect(service.registrationCount == 0)
        preferences.setEnabled(true)
        #expect(preferences.isEnabled)
        #expect(service.registrationCount == 1)
        preferences.setEnabled(true)
        #expect(service.registrationCount == 1)
        preferences.setEnabled(false)
        #expect(!preferences.isEnabled)
        #expect(service.unregistrationCount == 1)
    }

    @Test func pendingApprovalCanBeCancelledAndExternalChangesAreRefreshed() {
        let service = TestLoginItemService()
        service.registrationStatus = .requiresApproval
        let preferences = LoginItemPreferences(service: service)

        preferences.setEnabled(true)
        #expect(preferences.isEnabled)
        #expect(preferences.requiresApproval)
        preferences.setEnabled(true)
        #expect(service.registrationCount == 1)
        preferences.setEnabled(false)
        #expect(!preferences.isEnabled)
        #expect(!preferences.requiresApproval)

        service.status = .enabled
        preferences.refresh()
        #expect(preferences.isEnabled)
        service.status = .notRegistered
        preferences.refresh()
        #expect(!preferences.isEnabled)
    }

    @Test func failuresKeepTheSystemStateAndAllowRetry() {
        let service = TestLoginItemService()
        let preferences = LoginItemPreferences(service: service)
        service.shouldFail = true

        preferences.setEnabled(true)
        #expect(!preferences.isEnabled)
        #expect(preferences.errorMessage != nil)
        service.shouldFail = false
        preferences.setEnabled(true)
        #expect(preferences.isEnabled)
        #expect(preferences.errorMessage == nil)

        service.shouldFail = true
        preferences.setEnabled(false)
        #expect(preferences.isEnabled)
        #expect(preferences.errorMessage != nil)
    }
}

@MainActor
private final class TestLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var registrationCount = 0
    var unregistrationCount = 0
    var shouldFail = false

    func register() throws {
        registrationCount += 1
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = registrationStatus
    }

    func unregister() throws {
        unregistrationCount += 1
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}

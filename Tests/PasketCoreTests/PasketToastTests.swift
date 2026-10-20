import Testing
@testable import PasketCore

@Suite @MainActor
struct PasketToastTests {
    @Test func completionDoesNotLoseAnUnresolvedStorageError() throws {
        let center = PasketToastCenter()
        center.show("Retry saving.", source: .storage, title: "Storage Error",
                    style: .error, action: .retryStorage)
        let storage = try #require(center.current)
        center.show("Files removed.", source: .notice, title: "Cleanup Complete", style: .success)
        let completion = try #require(center.current)
        #expect(completion.duration == .seconds(4))
        center.dismiss(id: completion.id)
        #expect(center.current == storage)
        #expect(center.current?.duration == nil)
    }

    @Test func repeatedMessagesRestartPresentationAndIgnoreAnOldTimeout() throws {
        let center = PasketToastCenter()
        center.show("Files removed.", source: .notice, title: "Cleanup Complete", style: .success)
        let previous = try #require(center.current)
        center.show("Files removed.", source: .notice, title: "Cleanup Complete", style: .success)
        let repeated = try #require(center.current)
        #expect(previous.id != repeated.id)
        #expect(center.messages.count == 1)
        center.dismiss(id: previous.id)
        #expect(center.current == repeated)
    }

    @Test func resolvingAQueuedProblemLeavesTheCurrentNotificationVisible() throws {
        let center = PasketToastCenter()
        center.show("Retry saving.", source: .storage, title: "Storage Error",
                    style: .error, action: .retryStorage)
        center.show("Files removed.", source: .notice, title: "Cleanup Complete", style: .success)
        let completion = try #require(center.current)
        center.show(nil, source: .storage, title: "Storage Error", style: .error, action: .retryStorage)
        #expect(center.current == completion)
        center.dismiss(id: completion.id)
        #expect(center.current == nil)
    }

    @Test func closingHistoryClearsTransientMessagesAndKeepsRecoveryActions() {
        let center = PasketToastCenter()
        center.show("Retry saving.", source: .storage, title: "Storage Error",
                    style: .error, action: .retryStorage)
        center.show("Files removed.", source: .notice, title: "Cleanup Complete", style: .success)
        center.dismissTransient()
        #expect(center.messages.count == 1)
        #expect(center.current?.action == .retryStorage)
    }
}

import Testing
@testable import PasketCore

@Suite @MainActor
struct AppRelaunchTests {
    @Test func replacementWaitsUntilPreviousProcessExits() async {
        var running = true
        var waits = 0
        let ready = await AppRelaunch.waitForTermination(isRunning: { running }, wait: {
            waits += 1
            if waits == 3 { running = false }
        })
        #expect(ready)
        #expect(waits == 3)
        #expect(!running)
    }

    @Test func anExitedProcessDoesNotDelayStartup() async {
        var waits = 0
        let ready = await AppRelaunch.waitForTermination(isRunning: { false }, wait: { waits += 1 })
        #expect(ready)
        #expect(waits == 0)
    }

    @Test func timeoutDoesNotStartAnotherHistoryWriter() async {
        var waits = 0
        let ready = await AppRelaunch.waitForTermination(isRunning: { true }, wait: { waits += 1 }, attempts: 3)
        #expect(!ready)
        #expect(waits == 3)
    }

    @Test func interruptedWaitDoesNotStartTheReplacement() async {
        let ready = await AppRelaunch.waitForTermination(isRunning: { true }, wait: { throw CancellationError() })
        #expect(!ready)
    }
}

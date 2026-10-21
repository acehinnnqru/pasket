import Carbon.HIToolbox
import Testing
@testable import PasketCore

@Suite @MainActor
struct ClipboardPasteTests {
    @Test func queueAfterSetupDismissesHistoryAndWaitsForTheOriginalAppToReactivate() async {
        let fixture = Fixture()
        fixture.active = false
        var pasketIsActive = true
        let target = ClipboardPasteController.Target(processIdentifier: 42,
            isActive: { fixture.active }, isTerminated: { fixture.terminated },
            canRestoreFocus: { pasketIsActive })
        fixture.onWait = {
            if fixture.waits == 3 {
                fixture.active = true
                pasketIsActive = false
            }
        }
        let queue = ClipboardPasteQueue(clipboardChangeCount: { fixture.changeCount })
        let items = ["A", "B"].map { ClipboardItem.text($0, source: .unknown, at: .now) }
        #expect(queue.start(items))
        let delivered = await queue.advance(copy: { _, _ in
            #expect(target.canPrepareForPaste)
            return fixture.changeCount
        }, paste: { count in
            await fixture.controller.paste(to: target, expectedChangeCount: count, dismiss: fixture.dismiss)
        })
        #expect(delivered)
        #expect(fixture.events == ["wait", "dismiss", "wait", "wait", "paste:42"])
        #expect(queue.next?.id == items[1].id)
        #expect(fixture.controller.toasts.current == nil)
        queue.cancel()
    }

    @Test func failedFocusRestorationNeverPostsAPaste() async {
        let fixture = Fixture()
        fixture.active = false
        let target = ClipboardPasteController.Target(processIdentifier: 42,
            isActive: { fixture.active }, isTerminated: { false }, canRestoreFocus: { true })
        #expect(await fixture.controller.paste(to: target, dismiss: fixture.dismiss) == false)
        #expect(fixture.events.contains("dismiss"))
        #expect(!fixture.events.contains("paste:42"))
    }

    @Test func switchingToAnotherAppDuringFocusRestorationStopsTheQueue() async {
        let fixture = Fixture()
        fixture.active = false
        var pasketIsActive = true
        let target = ClipboardPasteController.Target(processIdentifier: 42,
            isActive: { false }, isTerminated: { false }, canRestoreFocus: { pasketIsActive })
        fixture.onWait = { if fixture.waits == 2 { pasketIsActive = false } }
        let queue = ClipboardPasteQueue(clipboardChangeCount: { fixture.changeCount })
        #expect(queue.start([ClipboardItem.text("A", source: .unknown, at: .now)]))
        #expect(await queue.advance(copy: { _, _ in fixture.changeCount }, paste: { count in
            await fixture.controller.paste(to: target, expectedChangeCount: count, dismiss: fixture.dismiss)
        }) == false)
        #expect(fixture.events == ["wait", "dismiss", "wait"])
        #expect(!queue.isActive)
    }

    @Test func postsTheDestinationShortcutAndWaitsForTheInvocationKeyToBeReleased() async {
        let fixture = Fixture()
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(controlKey), keyLabel: "Y")
        fixture.released = false
        fixture.onWait = { if fixture.waits == 3 { fixture.released = true } }
        let target = ClipboardPasteController.Target(processIdentifier: 42, isActive: { true }, isTerminated: { false })
        let pasted = await fixture.controller.paste(to: target, using: shortcut,
                                                     invocationKeyCode: UInt32(kVK_ANSI_N), dismiss: fixture.dismiss)
        #expect(pasted)
        #expect(fixture.postedShortcut == shortcut)
        #expect(fixture.releaseKeyCode == UInt32(kVK_ANSI_N))
        #expect(fixture.waits == 4)
        #expect(fixture.events.filter { $0 == "paste:42" }.count == 1)
    }

    @Test func clipboardChangedBeforeThePasteRequestNeverDeliversUnrelatedContent() async {
        let fixture = Fixture()
        let target = ClipboardPasteController.Target(processIdentifier: 42, isActive: { true }, isTerminated: { false })
        #expect(await fixture.controller.paste(to: target, expectedChangeCount: -1, dismiss: fixture.dismiss) == false)
        #expect(fixture.events.isEmpty)
    }

    @Test func dismissesBeforePastingIntoOriginalProcess() async {
        let fixture = Fixture()
        let pasted = await fixture.paste()
        #expect(pasted)
        #expect(fixture.events == ["wait", "dismiss", "wait", "paste:42"])
    }

    @Test func waitsForReturnAndModifiersToBeReleased() async {
        let fixture = Fixture()
        fixture.released = false
        fixture.onWait = { if fixture.waits == 3 { fixture.released = true } }
        #expect(await fixture.paste())
        #expect(fixture.waits == 4)
        #expect(fixture.events.firstIndex(of: "dismiss") == 3)
        #expect(fixture.events.last == "paste:42")
    }

    @Test func missingPermissionKeepsPanelOpenWithManualPasteInstructions() async {
        let fixture = Fixture()
        fixture.allowed = false
        #expect(await fixture.paste() == false)
        #expect(fixture.events.isEmpty)
        #expect(fixture.controller.needsPermission)
        #expect(fixture.controller.errorMessage?.contains("Paste command") == true)
        #expect(fixture.controller.toasts.current == nil)
        #expect(fixture.controller.systemAccess.request?.permission == .accessibility)
        fixture.controller.prepareForPresentation()
        #expect(fixture.controller.toasts.current == nil)
        #expect(fixture.controller.systemAccess.request == nil)
    }

    @Test func openingHistoryWithoutPastingDoesNotRequestPermission() {
        let fixture = Fixture()
        fixture.allowed = false
        fixture.controller.prepareForPresentation()
        #expect(fixture.controller.systemAccess.request == nil)
        #expect(fixture.events.isEmpty)
    }

    @Test func cancelledPermissionDialogOnlyReturnsOnAnotherPasteAttempt() async {
        let fixture = Fixture()
        fixture.allowed = false
        #expect(await fixture.paste() == false)
        fixture.controller.systemAccess.dismiss()
        #expect(fixture.controller.systemAccess.request == nil)
        #expect(fixture.events.isEmpty)
        #expect(await fixture.paste() == false)
        #expect(fixture.controller.systemAccess.request?.permission == .accessibility)
        #expect(fixture.events.isEmpty)
    }

    @Test func allowingAccessDoesNotReplayAPasteWithoutANewAttempt() async {
        let fixture = Fixture()
        fixture.allowed = false
        #expect(await fixture.paste() == false)
        fixture.controller.systemAccess.dismiss()
        fixture.allowed = true
        #expect(fixture.events.isEmpty)
        #expect(await fixture.paste())
        #expect(fixture.controller.systemAccess.request == nil)
    }

    @Test func missingOrTerminatedTargetNeverPastes() async {
        let fixture = Fixture()
        #expect(await fixture.controller.paste(to: nil, dismiss: fixture.dismiss) == false)
        fixture.terminated = true
        #expect(await fixture.paste() == false)
        #expect(fixture.events.isEmpty)
        #expect(fixture.controller.errorMessage != nil)
        #expect(fixture.controller.systemAccess.request == nil)
    }

    @Test func switchingAppsCancelsThePendingPaste() async {
        let fixture = Fixture()
        fixture.onWait = { fixture.active = false }
        #expect(await fixture.paste() == false)
        #expect(fixture.events == ["wait"])
    }

    @Test func targetExitingCancelsThePendingPaste() async {
        let fixture = Fixture()
        fixture.onWait = { fixture.terminated = true }
        #expect(await fixture.paste() == false)
        #expect(!fixture.events.contains("paste:42"))
    }

    @Test func clipboardChangesCancelThePendingPaste() async {
        let fixture = Fixture()
        fixture.onWait = { fixture.changeCount += 1 }
        #expect(await fixture.paste() == false)
        #expect(!fixture.events.contains("paste:42"))
    }

    @Test func reopeningOrDismissingCancelsThePendingPaste() async {
        let fixture = Fixture()
        fixture.onWait = { fixture.controller.prepareForPresentation() }
        #expect(await fixture.paste() == false)
        #expect(!fixture.events.contains("paste:42"))
    }

    @Test func permissionRevokedBeforePostingNeverPastes() async {
        let fixture = Fixture()
        fixture.onWait = { fixture.allowed = false }
        #expect(await fixture.paste() == false)
        #expect(!fixture.events.contains("paste:42"))
    }

    @Test func switchingAppsAfterDismissalStillCancelsThePaste() async {
        let fixture = Fixture()
        fixture.onWait = { if fixture.waits == 2 { fixture.active = false } }
        #expect(await fixture.paste() == false)
        #expect(fixture.events == ["wait", "dismiss", "wait"])
    }

    @Test func reopeningAfterDismissalStillCancelsThePaste() async {
        let fixture = Fixture()
        fixture.onWait = { if fixture.waits == 2 { fixture.controller.prepareForPresentation() } }
        #expect(await fixture.paste() == false)
        #expect(fixture.events == ["wait", "dismiss", "wait"])
    }

    @Test func changingClipboardAfterDismissalStillCancelsThePaste() async {
        let fixture = Fixture()
        fixture.onWait = { if fixture.waits == 2 { fixture.changeCount += 1 } }
        #expect(await fixture.paste() == false)
        #expect(fixture.events == ["wait", "dismiss", "wait"])
    }

    @Test func heldKeysTimeOutWithoutPostingOrRetryingLater() async {
        let fixture = Fixture()
        fixture.released = false
        #expect(await fixture.paste() == false)
        #expect(fixture.waits == 50)
        #expect(!fixture.events.contains("dismiss"))
        #expect(!fixture.events.contains("paste:42"))
    }

    @Test func failedEventCreationDoesNotReportSuccess() async {
        let fixture = Fixture()
        fixture.canPost = false
        #expect(await fixture.paste() == false)
    }

    @Test func cancelledTaskDoesNotPaste() async {
        let fixture = Fixture()
        let task = Task { await fixture.paste() }
        task.cancel()
        #expect(await task.value == false)
        #expect(!fixture.events.contains("paste:42"))
    }
}

@MainActor private final class Fixture {
    var active = true
    var terminated = false
    var allowed = true
    var released = true
    var canPost = true
    var changeCount = 1
    var waits = 0
    var events: [String] = []
    var onWait: (() -> Void)?
    var postedShortcut: GlobalShortcut?
    var releaseKeyCode: UInt32?

    lazy var controller = ClipboardPasteController(
        hasAccess: { self.allowed },
        inputReleased: { code in self.releaseKeyCode = code; return self.released },
        clipboardChangeCount: { self.changeCount },
        postPaste: { pid, shortcut in
            self.postedShortcut = shortcut
            self.events.append("paste:\(pid)")
            return self.canPost
        },
        wait: {
            self.waits += 1
            self.events.append("wait")
            self.onWait?()
        }
    )

    func dismiss() {
        events.append("dismiss")
        controller.cancel()
    }

    func paste() async -> Bool {
        await controller.paste(to: .init(processIdentifier: 42,
                                         isActive: { self.active },
                                         isTerminated: { self.terminated }), dismiss: dismiss)
    }
}

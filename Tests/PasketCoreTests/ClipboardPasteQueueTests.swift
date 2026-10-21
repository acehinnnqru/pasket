import Foundation
import Testing
@testable import PasketCore

@MainActor
struct ClipboardPasteQueueTests {
    private func items() -> [ClipboardItem] {
        ["A", "B", "C"].map { ClipboardItem.text($0, source: .unknown, at: .now) }
    }

    @Test func eachInvocationDeliversExactlyOneItemInSnapshotOrder() async {
        var count = 10
        let queue = ClipboardPasteQueue(clipboardChangeCount: { count })
        let items = items().reversed().map { $0 }
        var activeStates: [Bool] = []
        queue.onActiveChange = { activeStates.append($0) }
        #expect(queue.start(items))
        var copied: [UUID] = []
        var pastes = 0
        for (index, item) in items.enumerated() {
            #expect(queue.next?.id == item.id)
            #expect(queue.remainingCount == items.count - index)
            let delivered = await queue.advance(copy: { id, isCurrent in
                #expect(isCurrent())
                copied.append(id)
                count += 1
                return count
            }, paste: { expected in
                #expect(expected == count)
                pastes += 1
                return true
            })
            #expect(delivered)
            #expect(pastes == index + 1)
        }
        #expect(copied == items.map(\.id))
        #expect(!queue.isActive)
        #expect(activeStates == [true, false])
    }

    @Test func anExternalCopyCancelsBeforeAnotherItemIsWritten() async {
        var count = 10
        let queue = ClipboardPasteQueue(clipboardChangeCount: { count })
        queue.start(items())
        count += 1
        var writes = 0
        #expect(await queue.advance(copy: { _, _ in writes += 1; return count }, paste: { _ in true }) == false)
        #expect(writes == 0)
        #expect(!queue.isActive)
    }

    @Test func failedCopyOrPasteStopsWithoutSkippingOrReplaying() async {
        for copySucceeds in [false, true] {
            let queue = ClipboardPasteQueue(clipboardChangeCount: { 10 })
            queue.start(items())
            var pastes = 0
            #expect(await queue.advance(copy: { _, _ in copySucceeds ? 10 : nil }, paste: { _ in pastes += 1; return false }) == false)
            #expect(pastes == (copySucceeds ? 1 : 0))
            #expect(!queue.isActive)
            #expect(await queue.advance(copy: { _, _ in 10 }, paste: { _ in pastes += 1; return true }) == false)
            #expect(pastes == (copySucceeds ? 1 : 0))
        }
    }

    @Test func cancellationInvalidatesAnInFlightCopyAndCannotStartAReplacementUntilItReturns() async {
        let queue = ClipboardPasteQueue(clipboardChangeCount: { 10 })
        let items = items()
        queue.start(items)
        var pastes = 0
        let delivered = await queue.advance(copy: { _, isCurrent in
            queue.cancel()
            #expect(!isCurrent())
            #expect(!queue.start(items))
            return 10
        }, paste: { _ in pastes += 1; return true })
        #expect(!delivered)
        #expect(pastes == 0)
        #expect(!queue.isPasting)
        #expect(queue.start(items))
        queue.cancel()
    }

    @Test func overlappingInvocationsNeverPasteTwoItems() async {
        let queue = ClipboardPasteQueue(clipboardChangeCount: { 10 })
        queue.start(items())
        var pastes = 0
        let delivered = await queue.advance(copy: { _, _ in
            #expect(await queue.advance(copy: { _, _ in 10 }, paste: { _ in pastes += 1; return true }) == false)
            return 10
        }, paste: { _ in pastes += 1; return true })
        #expect(delivered)
        #expect(pastes == 1)
        #expect(queue.remainingCount == 2)
        queue.cancel()
    }

    @Test func clipboardChangeDuringDeliveryStopsTheQueue() async {
        var count = 10
        let queue = ClipboardPasteQueue(clipboardChangeCount: { count })
        queue.start(items())
        #expect(await queue.advance(copy: { _, _ in count += 1; return count }, paste: { _ in
            count += 1
            return true
        }) == false)
        #expect(!queue.isActive)
    }

    @Test func clipboardChangeAfterCopyDoesNotDeliverUnrelatedContent() async {
        var count = 10
        let queue = ClipboardPasteQueue(clipboardChangeCount: { count })
        queue.start(items())
        var pastes = 0
        #expect(await queue.advance(copy: { _, _ in
            count = 12
            return 11
        }, paste: { _ in pastes += 1; return true }) == false)
        #expect(pastes == 0)
        #expect(!queue.isActive)
    }
}

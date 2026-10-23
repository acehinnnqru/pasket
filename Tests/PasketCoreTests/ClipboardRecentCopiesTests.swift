import Foundation
import Testing
@testable import PasketCore

struct ClipboardRecentCopiesTests {
    @Test func batchesStopAtLongGapsAndExpireAfterFiveMinutes() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let ids = (0..<4).map { _ in UUID() }
        var copies = ClipboardRecentCopies()
        for (id, age) in zip(ids, [200.0, 100, 40, 0]) {
            copies.record(id, at: now.addingTimeInterval(-age))
        }
        #expect(copies.batch(at: now) == [ids[3], ids[2], ids[1]])
        #expect(copies.batch(at: now.addingTimeInterval(301)).isEmpty)
    }

    @Test func continuousCopyingCannotExtendTheBatchBeyondFiveMinutes() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let ids = (0..<8).map { _ in UUID() }
        var copies = ClipboardRecentCopies()
        for (index, id) in ids.enumerated() {
            copies.record(id, at: now.addingTimeInterval(Double(index - 7) * 50))
        }
        #expect(copies.batch(at: now) == Array(ids[1...].reversed()))
    }

    @Test func repeatedCopiesStayUniqueAndUseTheirLatestPosition() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let first = UUID(), second = UUID()
        var copies = ClipboardRecentCopies()
        copies.record(first, at: now.addingTimeInterval(-100))
        copies.record(second, at: now.addingTimeInterval(-50))
        copies.record(first, at: now)
        #expect(copies.batch(at: now) == [first, second])
    }
}

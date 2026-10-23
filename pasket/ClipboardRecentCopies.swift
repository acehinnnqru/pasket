import Foundation

nonisolated struct ClipboardRecentCopies {
    private struct Copy {
        let id: UUID
        let date: Date
    }

    private var copies: [Copy] = []
    private let maximumAge: TimeInterval = 5 * 60
    private let maximumGap: TimeInterval = 60

    mutating func record(_ id: UUID, at date: Date) {
        copies.removeAll { date.timeIntervalSince($0.date) > maximumAge }
        copies.append(Copy(id: id, date: date))
    }

    func batch(at date: Date) -> [UUID] {
        var result: [UUID] = []
        var seen: Set<UUID> = []
        var previous: Date?
        for copy in copies.reversed() {
            let age = date.timeIntervalSince(copy.date)
            guard age >= 0, age <= maximumAge else { break }
            if let previous, previous.timeIntervalSince(copy.date) > maximumGap { break }
            if seen.insert(copy.id).inserted { result.append(copy.id) }
            previous = copy.date
        }
        return result
    }
}

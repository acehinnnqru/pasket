import AppKit
import Observation

@MainActor @Observable
final class ClipboardPasteQueue {
    struct Entry: Identifiable {
        let id: UUID
        let title: String
    }

    private(set) var entries: [Entry] = []
    private(set) var isPasting = false
    var isActive: Bool { !entries.isEmpty }
    var next: Entry? { entries.first }
    var remainingCount: Int { entries.count }
    var onActiveChange: ((Bool) -> Void)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var expectedChangeCount: Int?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let clipboardChangeCount: () -> Int

    init(clipboardChangeCount: @escaping () -> Int = { NSPasteboard.general.changeCount }) {
        self.clipboardChangeCount = clipboardChangeCount
    }

    @discardableResult
    func start(_ items: [ClipboardItem]) -> Bool {
        guard !isPasting, !items.isEmpty else { return false }
        cancel()
        entries = items.map { Entry(id: $0.id, title: $0.title) }
        expectedChangeCount = clipboardChangeCount()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.checkClipboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onActiveChange?(true)
        return isActive
    }

    func cancel() {
        let wasActive = isActive
        generation = UUID()
        entries = []
        expectedChangeCount = nil
        timer?.invalidate()
        timer = nil
        if wasActive { onActiveChange?(false) }
    }

    @discardableResult
    func checkClipboard() -> Bool {
        guard isActive else { return false }
        if !isPasting, clipboardChangeCount() != expectedChangeCount { cancel() }
        return isActive
    }

    @discardableResult
    func advance(copy: (UUID, () -> Bool) async -> Int?, paste: (Int) async -> Bool) async -> Bool {
        guard !isPasting, checkClipboard(), let entry = next else { return false }
        isPasting = true
        defer { isPasting = false }
        let request = generation
        let copiedCount = await copy(entry.id, { self.generation == request && !Task.isCancelled })
        guard generation == request else { return false }
        guard let copiedCount, !Task.isCancelled, clipboardChangeCount() == copiedCount else { cancel(); return false }
        expectedChangeCount = copiedCount
        let pasted = await paste(copiedCount)
        guard generation == request else { return false }
        guard pasted, !Task.isCancelled, clipboardChangeCount() == expectedChangeCount else {
            cancel()
            return false
        }
        entries.removeFirst()
        if entries.isEmpty {
            timer?.invalidate()
            timer = nil
            expectedChangeCount = nil
            onActiveChange?(false)
        }
        return true
    }
}

import Foundation
import Observation

enum ClipboardFilterMemory: String, CaseIterable, Identifiable {
    case never, thirtySeconds, oneMinute, fiveMinutes, untilQuit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .untilQuit: "Until Pasket quits"
        }
    }

    var explanation: String {
        switch self {
        case .never:
            "Open history with All Types every time."
        case .thirtySeconds, .oneMinute, .fiveMinutes:
            "Keep the type filter when you reopen history within \(title) of closing it. After that, reopen with All Types."
        case .untilQuit:
            "Keep the type filter between opens until Pasket quits."
        }
    }

    func retainsFilter(closedAt: Date?, reopeningAt date: Date) -> Bool {
        guard let closedAt else { return false }
        let elapsed = date.timeIntervalSince(closedAt)
        guard elapsed >= 0 else { return false }
        switch self {
        case .never: return false
        case .thirtySeconds: return elapsed < 30
        case .oneMinute: return elapsed < 60
        case .fiveMinutes: return elapsed < 300
        case .untilQuit: return true
        }
    }
}

@MainActor @Observable
final class ClipboardFilterPreferences {
    private(set) var memory: ClipboardFilterMemory
    @ObservationIgnored private let defaults: UserDefaults

    private static let storageKey = "clipboardFilterMemory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        memory = defaults.string(forKey: Self.storageKey).flatMap(ClipboardFilterMemory.init(rawValue:)) ?? .oneMinute
    }

    func select(_ memory: ClipboardFilterMemory) {
        guard self.memory != memory else { return }
        defaults.set(memory.rawValue, forKey: Self.storageKey)
        self.memory = memory
    }
}

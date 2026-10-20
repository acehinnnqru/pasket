import AppKit

@MainActor
enum AppRelaunch {
    static let previousProcessArgument = "--pasket-relaunch-from"

    static func launchReplacement() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = [previousProcessArgument, String(ProcessInfo.processInfo.processIdentifier)]
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    static func waitForPreviousInstance() async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: previousProcessArgument),
              arguments.indices.contains(index + 1), let pid = pid_t(arguments[index + 1]),
              pid != ProcessInfo.processInfo.processIdentifier,
              let previous = NSRunningApplication(processIdentifier: pid),
              previous.bundleURL?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL else { return true }
        return await waitForTermination(isRunning: { !previous.isTerminated })
    }

    // The replacement must not load history or register shortcuts while the old process is alive.
    static func waitForTermination(isRunning: () -> Bool,
                                   wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) },
                                   attempts: Int = 100) async -> Bool {
        for _ in 0..<attempts {
            guard !Task.isCancelled else { return false }
            if !isRunning() { return true }
            do { try await wait() } catch { return false }
        }
        return !Task.isCancelled && !isRunning()
    }
}

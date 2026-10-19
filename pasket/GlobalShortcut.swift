import AppKit
import Carbon.HIToolbox
import Observation

struct GlobalShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey),
        keyLabel: "P"
    )

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    static func from(_ event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }

        let specialKeys: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        let label: String
        if let special = specialKeys[Int(event.keyCode)] {
            label = special
        } else if let characters = event.charactersIgnoringModifiers,
                  !characters.isEmpty,
                  !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            label = characters.uppercased()
        } else {
            return nil
        }

        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }
}

@MainActor @Observable
final class GlobalShortcutManager {
    private(set) var shortcut: GlobalShortcut
    private(set) var errorMessage: String?
    private(set) var isRecording = false
    var onInvoke: (() -> Void)?

    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var activeID: UInt32 = 0
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "globalInvocationShortcut"
    private static let signature: OSType = 0x50534B54

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
    }

    func start() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return status }
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue()
                    guard identifier.signature == GlobalShortcutManager.signature, identifier.id == manager.activeID,
                          !manager.isRecording else { return OSStatus(eventNotHandledErr) }
                    manager.onInvoke?()
                    return noErr
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            errorMessage = "Could not start global shortcuts (status \(status)). Relaunch Pasket to try again."
            return
        }
        _ = register(shortcut, persist: false)
    }

    func stop() {
        unregisterHotKey()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    func beginRecording() {
        guard handler != nil else {
            errorMessage = "Global shortcuts are unavailable. Relaunch Pasket to try again."
            return
        }
        unregisterHotKey()
        errorMessage = nil
        isRecording = true
    }

    func record(_ event: NSEvent) {
        guard isRecording, !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }
        guard let candidate = GlobalShortcut.from(event) else {
            errorMessage = "Include Command, Control, or Option with another key."
            return
        }
        if register(candidate, persist: true) { isRecording = false }
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        _ = register(shortcut, persist: false)
    }

    func restoreDefault() {
        _ = register(.default, persist: true)
    }

    @discardableResult
    private func register(_ candidate: GlobalShortcut, persist: Bool) -> Bool {
        guard handler != nil else {
            errorMessage = "Global shortcuts are unavailable. Relaunch Pasket to try again."
            return false
        }
        if hotKey != nil, candidate == shortcut {
            errorMessage = nil
            return true
        }

        var replacement: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
        nextID &+= 1
        let status = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, identifier, GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else {
            errorMessage = "This shortcut could not be registered. It may already be in use (status \(status)). Choose another combination."
            return false
        }

        // Keep an existing shortcut active until its replacement registers successfully.
        unregisterHotKey()
        hotKey = replacement
        activeID = identifier.id
        shortcut = candidate
        errorMessage = nil
        if persist, let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return true
    }

    private func unregisterHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        activeID = 0
    }
}

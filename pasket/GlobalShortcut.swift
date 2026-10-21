import AppKit
import Carbon.HIToolbox
import Observation

nonisolated struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultSettings = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_Comma),
        modifiers: UInt32(cmdKey),
        keyLabel: ","
    )

    static let defaultPaste = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey), keyLabel: "V")

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let candidate = Self.from(event) else { return false }
        return hasSameKeys(as: candidate)
    }

    func hasSameKeys(as other: GlobalShortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
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
    enum RecordingAction {
        case showHistory
        case openSettings
        case deleteSelectedItem
        case pasteNext
        case pasteFallback

        var title: String {
            switch self {
            case .showHistory: "Show Clipboard History"
            case .openSettings: "Open Settings"
            case .deleteSelectedItem: "Delete Selected Item"
            case .pasteNext: "Paste Next"
            case .pasteFallback: "Paste Shortcut Fallback"
            }
        }
    }

    private(set) var shortcut: GlobalShortcut?
    private(set) var deletionShortcut: GlobalShortcut?
    private(set) var settingsShortcut: GlobalShortcut?
    private(set) var pasteNextShortcut: GlobalShortcut?
    private(set) var pasteFallbackShortcut: GlobalShortcut?
    private(set) var resolvedPasteShortcut = GlobalShortcut.defaultPaste
    var effectivePasteNextShortcut: GlobalShortcut { pasteNextShortcut ?? resolvedPasteShortcut }
    private(set) var errorMessage: String?
    private(set) var isRecording = false
    private(set) var recordingAction: RecordingAction = .showHistory
    private(set) var pendingShortcut: GlobalShortcut?
    private(set) var isClearingShortcut = false
    private(set) var isConfiguringPasteQueue = false
    private(set) var hasConfirmedPasteQueueShortcut = false
    var needsPasteQueueShortcutSetup: Bool { !hasConfirmedPasteQueueShortcut && pasteNextShortcut == nil }
    var canSaveRecording: Bool { pendingShortcut != nil || isClearingShortcut }
    var onInvoke: (() -> Void)?
    var onPasteNext: (() -> Void)?

    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var pasteNextHotKey: EventHotKeyRef?
    @ObservationIgnored private var activePasteNextID: UInt32 = 0
    @ObservationIgnored private var registeredPasteNextShortcut: GlobalShortcut?
    @ObservationIgnored private var detectedPasteShortcut: GlobalShortcut?
    @ObservationIgnored private let queueRegistration: ((GlobalShortcut, UInt32) -> OSStatus)?
    @ObservationIgnored private let queueUnregistration: (() -> Void)?
    @ObservationIgnored private var pasteQueueIsActive = false
    @ObservationIgnored private var pasteQueueIsSuspended = false
    @ObservationIgnored private var pressedIDs: Set<UInt32> = []
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var activeID: UInt32 = 0
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "globalInvocationShortcut"
    private static let deletionStorageKey = "deleteSelectedItemShortcut"
    private static let settingsStorageKey = "openSettingsShortcut"
    private static let pasteNextStorageKey = "pasteNextShortcut"
    private static let pasteFallbackStorageKey = "pasteFallbackShortcut"
    private static let pasteQueueSetupStorageKey = "pasteQueueShortcutConfirmed"
    private static let signature: OSType = 0x50534B54

    init(defaults: UserDefaults = .standard,
         queueRegistration: ((GlobalShortcut, UInt32) -> OSStatus)? = nil,
         queueUnregistration: (() -> Void)? = nil) {
        self.defaults = defaults
        self.queueRegistration = queueRegistration
        self.queueUnregistration = queueUnregistration
        hasConfirmedPasteQueueShortcut = defaults.bool(forKey: Self.pasteQueueSetupStorageKey)
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = saved
        }
        if let data = defaults.data(forKey: Self.deletionStorageKey),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data),
           shortcut?.hasSameKeys(as: saved) != true {
            deletionShortcut = saved
        }
        let candidate: GlobalShortcut?
        if let data = defaults.data(forKey: Self.settingsStorageKey) {
            candidate = (try? JSONDecoder().decode(GlobalShortcut.self, from: data)) ?? .defaultSettings
        } else if defaults.object(forKey: Self.settingsStorageKey) != nil {
            candidate = nil
        } else {
            candidate = .defaultSettings
        }
        // Preserve existing history and deletion bindings when introducing the settings shortcut.
        if let candidate, shortcut?.hasSameKeys(as: candidate) != true,
           deletionShortcut?.hasSameKeys(as: candidate) != true {
            settingsShortcut = candidate
        }
        if let data = defaults.data(forKey: Self.pasteNextStorageKey),
           let candidate = try? JSONDecoder().decode(GlobalShortcut.self, from: data),
           shortcut?.hasSameKeys(as: candidate) != true,
           deletionShortcut?.hasSameKeys(as: candidate) != true,
           settingsShortcut?.hasSameKeys(as: candidate) != true {
            pasteNextShortcut = candidate
        }
        if let data = defaults.data(forKey: Self.pasteFallbackStorageKey),
           let candidate = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            pasteFallbackShortcut = candidate
            resolvedPasteShortcut = candidate
        }
    }

    func start() {
        guard handler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return status }
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue()
                    guard identifier.signature == GlobalShortcutManager.signature,
                          !manager.isRecording else { return OSStatus(eventNotHandledErr) }
                    return manager.handleHotKey(id: identifier.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
                        ? noErr : OSStatus(eventNotHandledErr)
                }
            },
            2,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            errorMessage = "Could not start global shortcuts (status \(status)). Relaunch Pasket to try again."
            return
        }
        restoreRegistration()
    }

    func stop() {
        unregisterHotKey()
        unregisterPasteNext()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    @discardableResult
    func handleHotKey(id: UInt32, pressed: Bool) -> Bool {
        guard !isRecording, id != 0, id == activeID || id == activePasteNextID else { return false }
        if !pressed { pressedIDs.remove(id); return true }
        guard pressedIDs.insert(id).inserted else { return true }
        if id == activeID { onInvoke?() } else { onPasteNext?() }
        return true
    }

    func beginRecording(_ action: RecordingAction = .showHistory) {
        unregisterHotKey()
        unregisterPasteNext()
        errorMessage = nil
        pendingShortcut = nil
        isClearingShortcut = false
        recordingAction = action
        isConfiguringPasteQueue = false
        isRecording = true
    }

    func beginPasteQueueSetup() {
        beginRecording(.pasteNext)
        isConfiguringPasteQueue = true
        stageShortcut(pasteNextShortcut)
    }

    func record(_ event: NSEvent) {
        guard isRecording, !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }
        guard let candidate = GlobalShortcut.from(event) else {
            pendingShortcut = nil
            isClearingShortcut = false
            errorMessage = "Include Command, Control, or Option with another key."
            return
        }
        stageShortcut(candidate)
    }

    func stageShortcut(_ candidate: GlobalShortcut?) {
        guard isRecording else { return }
        pendingShortcut = candidate
        isClearingShortcut = candidate == nil
        errorMessage = nil
    }

    @discardableResult
    func saveRecording() -> Bool {
        guard isRecording, canSaveRecording else { return false }
        switch recordingAction {
        case .pasteNext:
            if isConfiguringPasteQueue, !pasteQueueIsActive {
                guard registerPasteNext(pendingShortcut ?? resolvedPasteShortcut) else { return false }
                unregisterPasteNext()
            }
            guard setPasteNextShortcut(pendingShortcut) else { return false }
        case .pasteFallback:
            guard setPasteFallbackShortcut(pendingShortcut) else { return false }
        case .deleteSelectedItem, .openSettings:
            let accepted = recordingAction == .openSettings
                ? setSettingsShortcut(pendingShortcut) : setDeletionShortcut(pendingShortcut)
            guard accepted else { return false }
        case .showHistory:
            guard let candidate = pendingShortcut else {
                unregisterHotKey()
                shortcut = nil
                defaults.removeObject(forKey: Self.storageKey)
                finishRecording()
                return true
            }
            guard settingsShortcut?.hasSameKeys(as: candidate) != true else {
                errorMessage = "This combination is assigned to Open Settings. Choose another combination."
                return false
            }
            guard deletionShortcut?.hasSameKeys(as: candidate) != true else {
                errorMessage = "This combination is assigned to Delete Selected Item. Choose another combination."
                return false
            }
            guard pasteNextShortcut?.hasSameKeys(as: candidate) != true else {
                errorMessage = "This combination is assigned to Paste Next. Choose another combination."
                return false
            }
            guard register(candidate, persist: true) else { return false }
        }
        finishRecording()
        return true
    }

    func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
    }

    private func finishRecording() {
        isRecording = false
        pendingShortcut = nil
        isClearingShortcut = false
        isConfiguringPasteQueue = false
        errorMessage = nil
        restoreRegistration()
    }

    private func restoreRegistration() {
        if handler != nil, let shortcut { _ = register(shortcut, persist: false) }
        if handler != nil || queueRegistration != nil, pasteQueueIsActive, !pasteQueueIsSuspended {
            _ = registerPasteNext(effectivePasteNextShortcut)
        }
    }

    @discardableResult
    func setDeletionShortcut(_ candidate: GlobalShortcut?) -> Bool {
        if let candidate, pasteNextShortcut?.hasSameKeys(as: candidate) == true {
            errorMessage = "This combination is assigned to Paste Next. Choose another combination."
            return false
        }
        if let candidate, settingsShortcut?.hasSameKeys(as: candidate) == true {
            errorMessage = "This combination is assigned to Open Settings. Choose another combination."
            return false
        }
        if let candidate, shortcut?.hasSameKeys(as: candidate) == true {
            errorMessage = "This combination opens clipboard history. Choose another combination."
            return false
        }
        deletionShortcut = candidate
        errorMessage = nil
        if let candidate, let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.deletionStorageKey)
        } else {
            defaults.removeObject(forKey: Self.deletionStorageKey)
        }
        return true
    }

    @discardableResult
    func setSettingsShortcut(_ candidate: GlobalShortcut?) -> Bool {
        if let candidate, pasteNextShortcut?.hasSameKeys(as: candidate) == true {
            errorMessage = "This combination is assigned to Paste Next. Choose another combination."
            return false
        }
        if let candidate {
            guard shortcut?.hasSameKeys(as: candidate) != true else {
                errorMessage = "This combination opens clipboard history. Choose another combination."
                return false
            }
            guard deletionShortcut?.hasSameKeys(as: candidate) != true else {
                errorMessage = "This combination is assigned to Delete Selected Item. Choose another combination."
                return false
            }
        }
        settingsShortcut = candidate
        errorMessage = nil
        if let candidate, let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.settingsStorageKey)
        } else {
            defaults.set(false, forKey: Self.settingsStorageKey)
        }
        return true
    }

    @discardableResult
    func setPasteNextShortcut(_ candidate: GlobalShortcut?) -> Bool {
        if let candidate {
            guard shortcut?.hasSameKeys(as: candidate) != true,
                  settingsShortcut?.hasSameKeys(as: candidate) != true,
                  deletionShortcut?.hasSameKeys(as: candidate) != true else {
                errorMessage = "This combination is assigned to another Pasket action. Choose another combination."
                return false
            }
            if pasteQueueIsActive && !pasteQueueIsSuspended {
                guard registerPasteNext(candidate) else { return false }
            }
        } else if pasteQueueIsActive && !pasteQueueIsSuspended {
            guard registerPasteNext(resolvedPasteShortcut) else { return false }
        }
        pasteNextShortcut = candidate
        hasConfirmedPasteQueueShortcut = true
        defaults.set(true, forKey: Self.pasteQueueSetupStorageKey)
        errorMessage = nil
        if let candidate, let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.pasteNextStorageKey)
        } else { defaults.removeObject(forKey: Self.pasteNextStorageKey) }
        return true
    }

    @discardableResult
    func setPasteQueueActive(_ active: Bool) -> Bool {
        pasteQueueIsActive = active
        if !active { unregisterPasteNext(); return true }
        guard !isRecording, !pasteQueueIsSuspended else { return true }
        return registerPasteNext(effectivePasteNextShortcut)
    }

    func suspendPasteQueueShortcut() {
        pasteQueueIsSuspended = true
        unregisterPasteNext()
    }

    @discardableResult
    func setPasteFallbackShortcut(_ candidate: GlobalShortcut?) -> Bool {
        let resolved = detectedPasteShortcut ?? candidate ?? .defaultPaste
        if pasteQueueIsActive, !pasteQueueIsSuspended, pasteNextShortcut == nil {
            guard registerPasteNext(resolved) else { return false }
        }
        pasteFallbackShortcut = candidate
        resolvedPasteShortcut = resolved
        if let candidate, let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.pasteFallbackStorageKey)
        } else { defaults.removeObject(forKey: Self.pasteFallbackStorageKey) }
        return true
    }

    @discardableResult
    func updatePasteDestination(detectedShortcut: GlobalShortcut?) -> Bool {
        pasteQueueIsSuspended = false
        detectedPasteShortcut = detectedShortcut
        resolvedPasteShortcut = detectedShortcut ?? pasteFallbackShortcut ?? .defaultPaste
        guard pasteQueueIsActive, !isRecording else { return true }
        return registerPasteNext(effectivePasteNextShortcut)
    }

    private func registerPasteNext(_ candidate: GlobalShortcut) -> Bool {
        guard shortcut?.hasSameKeys(as: candidate) != true,
              settingsShortcut?.hasSameKeys(as: candidate) != true,
              deletionShortcut?.hasSameKeys(as: candidate) != true else {
            errorMessage = "The app's paste shortcut conflicts with another Pasket action. Choose a different Paste Next shortcut in Settings."
            return false
        }
        guard handler != nil || queueRegistration != nil else {
            errorMessage = "Global shortcuts are unavailable. Relaunch Pasket to try again."
            return false
        }
        if registeredPasteNextShortcut?.hasSameKeys(as: candidate) == true { return true }
        var replacement: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
        nextID &+= 1
        let status: OSStatus
        if let queueRegistration { status = queueRegistration(candidate, identifier.id) }
        else {
            status = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        }
        guard status == noErr, queueRegistration != nil || replacement != nil else {
            errorMessage = "Paste Next could not be registered. It may already be in use (status \(status)). Choose another combination."
            return false
        }
        unregisterPasteNext()
        pasteNextHotKey = replacement
        registeredPasteNextShortcut = candidate
        activePasteNextID = identifier.id
        return true
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
        pressedIDs.remove(activeID)
        activeID = 0
    }

    private func unregisterPasteNext() {
        if registeredPasteNextShortcut != nil { queueUnregistration?() }
        if let pasteNextHotKey { UnregisterEventHotKey(pasteNextHotKey) }
        pasteNextHotKey = nil
        registeredPasteNextShortcut = nil
        pressedIDs.remove(activePasteNextID)
        activePasteNextID = 0
    }
}

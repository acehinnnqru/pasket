import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum PasteShortcutResolver {
    // Match only the standard Paste command, never variants such as Paste and Match Style.
    nonisolated static let standardPasteTitles: Set<String> = [
        "Paste", "粘贴", "貼上", "粘貼", "贴上", "ペースト", "붙여넣기", "Einsetzen", "Einfügen",
        "Coller", "Pegar", "Incolla", "Plakken", "Wklej", "Вставить", "Colar"
    ]
    struct MenuCommand {
        var title: String
        var identifier: String? = nil
        var virtualKey: Int
        var modifiers: Int
        var character: String
    }

    static func shortcut(from commands: [MenuCommand], pasteTitles: Set<String> = standardPasteTitles) -> GlobalShortcut? {
        let candidates = commands.compactMap { command -> GlobalShortcut? in
            guard pasteTitles.contains(command.title) || command.identifier == "paste:" else { return nil }
            guard (0..<128).contains(command.virtualKey), (0..<16).contains(command.modifiers) else { return nil }
            var modifiers: UInt32 = command.modifiers & 8 == 0 ? UInt32(cmdKey) : 0
            if command.modifiers & 1 != 0 { modifiers |= UInt32(shiftKey) }
            if command.modifiers & 2 != 0 { modifiers |= UInt32(optionKey) }
            if command.modifiers & 4 != 0 { modifiers |= UInt32(controlKey) }
            let label = command.character.isEmpty ? "Key \(command.virtualKey)" : command.character.uppercased()
            return GlobalShortcut(keyCode: UInt32(command.virtualKey), modifiers: modifiers, keyLabel: label)
        }
        guard let first = candidates.first, candidates.allSatisfy({ $0.hasSameKeys(as: first) }) else { return nil }
        return first
    }

    static func shortcut(for application: NSRunningApplication) -> GlobalShortcut? {
        guard AXIsProcessTrusted(), !application.isTerminated else { return nil }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let value = attribute(kAXMenuBarAttribute, of: app),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let menuBar = value as! AXUIElement
        var pasteTitles = standardPasteTitles
        if let title = NSTextView.defaultMenu?.items.first(where: { $0.action == #selector(NSText.paste(_:)) })?.title {
            pasteTitles.insert(title)
        }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
        var pending: [(AXUIElement, Int)] = [(menuBar, 0)]
        var commands: [MenuCommand] = []
        var visited = 0
        while let (element, depth) = pending.popLast() {
            guard visited < 256, ContinuousClock.now < deadline else {
                return shortcut(from: commands, pasteTitles: pasteTitles)
            }
            visited += 1
            let title = attribute(kAXTitleAttribute, of: element) as? String ?? ""
            let identifier = attribute(kAXIdentifierAttribute, of: element) as? String
            if pasteTitles.contains(title) || identifier == "paste:",
               let key = attribute(kAXMenuItemCmdVirtualKeyAttribute, of: element) as? NSNumber,
               let modifiers = attribute(kAXMenuItemCmdModifiersAttribute, of: element) as? NSNumber {
                commands.append(MenuCommand(title: title, identifier: identifier, virtualKey: key.intValue,
                                            modifiers: modifiers.intValue,
                                            character: attribute(kAXMenuItemCmdCharAttribute, of: element) as? String ?? ""))
            }
            if depth < 4, let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] {
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return shortcut(from: commands, pasteTitles: pasteTitles)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

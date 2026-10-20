import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ApplicationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shortcuts.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.shortcuts.stop()
        controller.store.stop()
        Task {
            await controller.finishPendingWork()
            if let error = controller.store.storageError, !controller.store.isStorageBlocked {
                let alert = NSAlert()
                alert.messageText = "History Has Unsaved Changes"
                alert.informativeText = error
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Quit Without Saving")
                if alert.runModal() == .alertFirstButtonReturn {
                    controller.store.resumeMonitoring()
                    controller.shortcuts.start()
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
final class ApplicationController: NSObject, NSWindowDelegate {
    let store = ClipboardStore()
    let shortcuts = GlobalShortcutManager()

    private var panel: ClipboardPanel?
    private var settingsWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var startupTask: Task<Void, Never>?
    private var settingsFieldEditor = SettingsFieldEditor()

    func start() {
        shortcuts.onInvoke = { [weak self] in self?.togglePanel() }
        shortcuts.start()
        startupTask = Task { await store.start() }
        showPanel()
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else if settingsWindow?.attachedSheet == nil {
            showPanel()
        }
    }

    func showPanel() {
        if panel?.isVisible == true {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        if panel == nil {
            let panel = ClipboardPanel(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: ContentView(
                store: store,
                shortcuts: shortcuts,
                onDismiss: { [weak self] in self?.hidePanel() },
                onOpenSettings: { [weak self] in self?.showSettings() },
                onRestoreFileAccess: { [weak self] item in self?.restoreFileAccess(item) }
            ))
            self.panel = panel
        }
        store.prepareForPresentation()
        if let panel {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visibleFrame.midX - panel.frame.width / 2, y: visibleFrame.midY - panel.frame.height / 2))
            }
            NSApplication.shared.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hidePanel(restorePreviousApplication: Bool = true) {
        let applicationToRestore = previousApplication
        previousApplication = nil
        store.invalidatePresentation()
        panel?.orderOut(nil)
        if restorePreviousApplication, let applicationToRestore, !applicationToRestore.isTerminated {
            applicationToRestore.activate()
        }
    }

    func showSettings() {
        let screen = (panel?.isVisible == true ? panel?.screen : nil)
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        hidePanel(restorePreviousApplication: false)
        if settingsWindow == nil {
            let window = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = "Pasket Settings"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ShortcutSettingsView(
                shortcuts: shortcuts,
                store: store,
                onClose: { [weak self] in self?.settingsWindow?.close() }
            ))
            settingsWindow = window
        }
        if let window = settingsWindow, let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        }
        NSApplication.shared.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private var isRestoringFileAccess = false

    func finishPendingWork() async {
        await startupTask?.value
        store.stop()
        await store.flush()
    }

    private func restoreFileAccess(_ item: ClipboardItem) {
        isRestoringFileAccess = true
        store.restoreFileAccess(item)
        isRestoringFileAccess = false
        panel?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel, !isRestoringFileAccess,
           window.attachedSheet == nil {
            hidePanel(restorePreviousApplication: false)
        }
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard sender === settingsWindow else { return nil }
        return settingsFieldEditor.editor(for: client)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        if shortcuts.isRecording { shortcuts.cancelRecording() }
        // Closing under the pointer may not send a hover exit to the hosted controls.
        // Recreate the window next time so transient interaction state cannot survive closing.
        settingsWindow = nil
        settingsFieldEditor = SettingsFieldEditor()
    }
}

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

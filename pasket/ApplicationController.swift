import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ApplicationController()
    private var launchTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        launchTask = Task {
            let ready = await AppRelaunch.waitForPreviousInstance()
            guard !Task.isCancelled else { return }
            guard ready else {
                NSApplication.shared.terminate(nil)
                return
            }
            controller.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shortcuts.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        launchTask?.cancel()
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
                    controller.resumeAfterCancelledTermination()
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            if controller.isRelaunchRequested {
                do {
                    try await AppRelaunch.launchReplacement()
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could Not Reopen Pasket"
                    alert.informativeText = "Pasket will stay open. Try quitting and reopening it manually. \(error.localizedDescription)"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    controller.resumeAfterCancelledTermination()
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
    let store: ClipboardStore
    let shortcuts = GlobalShortcutManager()
    let pasteController: ClipboardPasteController
    let dockIcon = DockIconPreferences()
    let accentColor = AccentColorPreferences()
    private(set) var isRelaunchRequested = false

    private var panel: ClipboardPanel?
    private var settingsWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var startupTask: Task<Void, Never>?
    private var settingsFieldEditor = SettingsFieldEditor()
    private var isHidingPanel = false

    override init() {
        let store = ClipboardStore()
        self.store = store
        pasteController = ClipboardPasteController(toasts: store.toasts, systemAccess: store.systemAccess)
        super.init()
        dockIcon.onChange = { [weak self] in self?.applyDockIcon() }
    }

    func start() {
        applyDockIcon()
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
        pasteController.prepareForPresentation()
        if panel?.isVisible == true {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        previousApplication = nil
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
                pasteController: pasteController,
                onDismiss: { [weak self] in self?.hidePanel() },
                onPasteCopiedItem: { [weak self] in self?.pasteCopiedItem() },
                onOpenSettings: { [weak self] in self?.showSettings() },
                onRelaunch: { [weak self] in self?.requestRelaunch() }
            ).modifier(PasketAccentColor(preferences: accentColor)))
            self.panel = panel
        }
        store.prepareForPresentation()
        if let panel {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visibleFrame.midX - panel.frame.width / 2, y: visibleFrame.midY - panel.frame.height / 2))
            }
            // Let the nonactivating panel borrow keyboard focus without deactivating the editor.
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hidePanel(restorePreviousApplication: Bool = true) {
        guard !isHidingPanel else { return }
        isHidingPanel = true
        defer { isHidingPanel = false }
        pasteController.cancel()
        let applicationToRestore = previousApplication
        previousApplication = nil
        store.invalidatePresentation()
        panel?.orderOut(nil)
        if restorePreviousApplication, let applicationToRestore,
           !applicationToRestore.isTerminated, !applicationToRestore.isActive {
            applicationToRestore.activate()
        }
    }

    private func pasteCopiedItem() {
        let target = previousApplication.map { ClipboardPasteController.Target(application: $0) }
        let presentation = store.presentationID
        Task {
            guard store.presentationID == presentation, panel?.isVisible == true else { return }
            await pasteController.paste(to: target) { [weak self] in self?.hidePanel() }
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
                dockIcon: dockIcon,
                accentColor: accentColor,
                onClose: { [weak self] in self?.settingsWindow?.close() }
            ).modifier(PasketAccentColor(preferences: accentColor)))
            settingsWindow = window
        }
        if let window = settingsWindow, let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        }
        NSApplication.shared.setActivationPolicy(.regular)
        applyDockIcon()
        NSApplication.shared.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func applyDockIcon() {
        guard let image = NSImage(named: NSImage.Name(dockIcon.color.assetName)) else { return }
        NSApplication.shared.applicationIconImage = image
    }

    func finishPendingWork() async {
        await startupTask?.value
        store.stop()
        await store.flush()
    }

    private func requestRelaunch() {
        guard !isRelaunchRequested else { return }
        isRelaunchRequested = true
        pasteController.cancel()
        store.systemAccess.dismiss()
        NSApplication.shared.terminate(nil)
    }

    func resumeAfterCancelledTermination() {
        isRelaunchRequested = false
        store.resumeMonitoring()
        shortcuts.start()
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isHidingPanel, let window = notification.object as? NSWindow, window === panel, window.isVisible,
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
        NSApplication.shared.setActivationPolicy(.accessory)
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

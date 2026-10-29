import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ApplicationController()
    private var launchTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Capture the launch event before yielding to the asynchronous startup task.
        let isLoginItemLaunch = AppLaunch.isLoginItemLaunch(NSAppleEventManager.shared().currentAppleEvent)
        launchTask = Task {
            let ready = await AppRelaunch.waitForPreviousInstance()
            guard !Task.isCancelled else { return }
            guard ready else {
                NSApplication.shared.terminate(nil)
                return
            }
            controller.start(showHistoryOnLaunch: !isLoginItemLaunch)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.reopen()
        return false
    }

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
    let appearance = AppearancePreferences()
    let loginItem = LoginItemPreferences()
    let setup = AppSetup()
    let historyStatistics = HistoryStatistics()
    private(set) var isRelaunchRequested = false

    private var panel: ClipboardPanel?
    private var settingsWindow: NSWindow?
    private var statisticsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var hasStartedHistory = false
    private var previousApplication: NSRunningApplication?
    private var startupTask: Task<Void, Never>?
    private var settingsFieldEditor = SettingsFieldEditor()
    private var isHidingPanel = false
    private var queueShortcutObserver: NSObjectProtocol?

    override init() {
        let store = ClipboardStore()
        self.store = store
        pasteController = ClipboardPasteController(toasts: store.toasts, systemAccess: store.systemAccess)
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        dockIcon.onChange = { [weak self] in self?.applyDockPreferences() }
        store.pasteQueue.onActiveChange = { [weak self] active in
            guard let self else { return }
            if !shortcuts.setPasteQueueActive(active) {
                store.pasteQueue.cancel()
                store.toasts.show(shortcuts.errorMessage, source: .notice, title: "Paste Queue Could Not Start", style: .warning)
            }
            if !active { pasteController.cancel() }
        }
    }

    func start(showHistoryOnLaunch: Bool = true) {
        applyDockPreferences()
        shortcuts.onInvoke = { [weak self] in self?.togglePanel() }
        shortcuts.onPasteNext = { [weak self] in self?.pasteNextQueuedItem() }
        shortcuts.start()
        if queueShortcutObserver == nil {
            queueShortcutObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.store.pasteQueue.isActive,
                          let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                        self.shortcuts.suspendPasteQueueShortcut()
                        return
                    }
                    self.resumePasteQueueShortcut()
                }
            }
        }
        setup.refresh(hasShortcut: shortcuts.shortcut != nil)
        if setup.step == .complete {
            finishSetup(showHistory: showHistoryOnLaunch)
        } else {
            showSetup()
        }
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else if settingsWindow?.attachedSheet == nil {
            showPanel()
        }
    }

    func reopen() {
        if setupWindow != nil {
            showSetup()
            return
        }
        if let window = statisticsWindow, window.isKeyWindow {
            bringWindowToFront(window)
        } else if settingsWindow?.isVisible == true {
            bringSettingsToFront()
        } else if let window = statisticsWindow, window.isVisible {
            bringWindowToFront(window)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard setupWindow == nil else { showSetup(); return }
        pasteController.prepareForPresentation()
        if panel?.isVisible == true {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        previousApplication = nil
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
            resumePasteQueueShortcut()
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
            // Join the invoking desktop without remaining over other Spaces during a switch.
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
                onStartPasteQueue: { [weak self] items in self?.startPasteQueue(items) },
                onPasteNext: { [weak self] in self?.pasteNextQueuedItem() },
                onRelaunch: { [weak self] in self?.requestRelaunch() }
            ).modifier(PasketAccentColor(preferences: accentColor))
                .modifier(PasketAppearance(preferences: appearance)))
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
            if panel.isVisible { historyStatistics.recordEvent() }
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
        let target = previousApplication.map { pasteTarget($0) }
        let presentation = store.presentationID
        guard let changeCount = store.copiedChangeCount else { return }
        Task {
            guard store.presentationID == presentation, panel?.isVisible == true else { return }
            await pasteController.paste(to: target, expectedChangeCount: changeCount) { [weak self] in self?.hidePanel() }
        }
    }

    private func startPasteQueue(_ items: [ClipboardItem]) {
        guard !store.isDebugMode, !store.isCopying, !store.isSearching,
              store.pasteQueue.start(items) else { return }
        pasteNextQueuedItem()
    }

    func pasteNextQueuedItem() {
        guard !shortcuts.isRecording, !store.pasteQueue.isPasting,
              store.pasteQueue.checkClipboard(), store.systemAccess.request == nil else { return }
        let application = panel?.isVisible == true ? previousApplication : NSWorkspace.shared.frontmostApplication
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              pasteTarget(application).canPrepareForPaste else {
            store.pasteQueue.cancel()
            store.toasts.show("Open history from the app where you want to paste, then choose Paste Next.",
                              source: .notice, title: "Choose a Paste Destination", style: .information)
            return
        }
        let target = pasteTarget(application)
        guard resumePasteQueueShortcut() else { return }
        let invocationKeyCode = shortcuts.pasteNextShortcut?.keyCode
        let presentation = store.presentationID
        Task {
            let delivered = await store.pasteQueue.advance(copy: { [self] id, isCurrent in
                guard target.canPrepareForPaste, store.presentationID == presentation else { return nil }
                let copied = await store.copyItem(id, isCurrent: {
                    isCurrent() && target.canPrepareForPaste
                        && store.presentationID == presentation
                })
                return copied ? store.copiedChangeCount : nil
            }, paste: { [self] changeCount in
                await pasteController.paste(to: target, invocationKeyCode: invocationKeyCode,
                                            expectedChangeCount: changeCount) { [weak self] in
                    if self?.panel?.isVisible == true { self?.hidePanel() }
                }
            })
            if !delivered, panel?.isVisible != true,
               pasteController.needsPermission || store.copyError != nil {
                let needsPermission = pasteController.needsPermission
                let message = store.copyError
                showPanel()
                if needsPermission { store.systemAccess.present(.accessibility) }
                else {
                    store.toasts.show(message, source: .notice, title: "Paste Queue Stopped", style: .warning)
                }
            }
        }
    }

    private func pasteTarget(_ application: NSRunningApplication) -> ClipboardPasteController.Target {
        let canRestoreFocus = panel?.isVisible == true
        return ClipboardPasteController.Target(application: application, canRestoreFocus: {
            canRestoreFocus && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        })
    }

    @discardableResult
    private func resumePasteQueueShortcut() -> Bool {
        guard shortcuts.resumePasteQueueShortcut() else {
            store.pasteQueue.cancel()
            store.toasts.show(shortcuts.errorMessage, source: .notice, title: "Paste Queue Stopped", style: .warning)
            return false
        }
        return true
    }

    func showSettings() {
        guard setupWindow == nil else { showSetup(); return }
        shortcuts.suspendPasteQueueShortcut()
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
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: ShortcutSettingsView(
                shortcuts: shortcuts,
                store: store,
                dockIcon: dockIcon,
                accentColor: accentColor,
                appearance: appearance,
                loginItem: loginItem,
                onClose: { [weak self] in self?.settingsWindow?.close() }
            ).modifier(PasketAccentColor(preferences: accentColor))
                .modifier(PasketAppearance(preferences: appearance)))
            settingsWindow = window
        }
        if let window = settingsWindow, let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        }
        bringSettingsToFront()
    }

    private func bringSettingsToFront() {
        guard let window = settingsWindow else { return }
        bringWindowToFront(window)
    }

    func showStatistics() {
        guard setupWindow == nil else { showSetup(); return }
        shortcuts.suspendPasteQueueShortcut()
        let screen = (panel?.isVisible == true ? panel?.screen : nil)
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        hidePanel(restorePreviousApplication: false)
        if statisticsWindow == nil {
            let window = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.title = "Pasket Statistics"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: HistoryStatisticsWindowView(
                statistics: historyStatistics,
                copyStatistics: store.copyStatistics,
                onClose: { [weak self] in self?.statisticsWindow?.close() }
            ).modifier(PasketAccentColor(preferences: accentColor))
                .modifier(PasketAppearance(preferences: appearance)))
            if let visibleFrame = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                ))
            }
            statisticsWindow = window
        }
        if let window = statisticsWindow { bringWindowToFront(window) }
    }

    private func bringWindowToFront(_ window: NSWindow) {
        // Let menu tracking finish before activating; closing the menu can restore the previous app.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window,
                  self.settingsWindow === window || self.statisticsWindow === window else { return }
            let application = NSApplication.shared
            application.unhide(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            application.activate()
            // Activation is a request, so also raise the window while AppKit processes it.
            window.orderFrontRegardless()
        }
    }

    private func showSetup() {
        if setupWindow == nil {
            let window = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.title = "Welcome to Pasket"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = false
            window.contentView = NSHostingView(rootView: PasketSetupView(
                setup: setup,
                shortcuts: shortcuts,
                onRequestPermission: { [weak self] permission in self?.requestSetupPermission(permission) },
                onFinish: { [weak self] in self?.finishSetup() },
                onRelaunch: { [weak self] in self?.requestRelaunch() },
                onResize: { [weak self] height in
                    DispatchQueue.main.async { [weak self] in
                        guard let window = self?.setupWindow, abs(window.frame.height - height) > 0.5 else { return }
                        var frame = window.frame
                        frame.origin.y = frame.maxY - height
                        frame.size.height = height
                        window.setFrame(frame, display: true)
                    }
                }
            ).modifier(PasketAccentColor(preferences: accentColor))
                .modifier(PasketAppearance(preferences: appearance)))
            window.center()
            setupWindow = window
        }
        NSApplication.shared.activate()
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    private func requestSetupPermission(_ permission: SystemAccessController.Permission) {
        switch permission {
        case .clipboard:
            // Trigger the system request so Pasket can appear in clipboard privacy settings.
            if NSPasteboard.general.accessBehavior == .default || NSPasteboard.general.accessBehavior == .ask {
                _ = NSPasteboard.general.string(forType: .string)
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard") {
                NSWorkspace.shared.open(url)
            }
        case .accessibility:
            pasteController.openAccessibilitySettings()
        }
    }

    private func finishSetup(showHistory: Bool = true) {
        guard setup.step == .complete else { return }
        if shortcuts.isRecording { shortcuts.cancelRecording() }
        setupWindow?.close()
        setupWindow = nil
        if !hasStartedHistory {
            hasStartedHistory = true
            startupTask = Task { await store.start() }
        }
        if showHistory { showPanel() }
    }

    private func applyDockPreferences() {
        let application = NSApplication.shared
        let policy: NSApplication.ActivationPolicy = dockIcon.showInDock ? .regular : .accessory
        if application.activationPolicy() != policy {
            let visibleSettingsWindow = settingsWindow.flatMap { $0.isVisible ? $0 : nil }
            let visibleStatisticsWindow = statisticsWindow.flatMap { $0.isVisible ? $0 : nil }
            application.setActivationPolicy(policy)
            if let window = visibleStatisticsWindow { bringWindowToFront(window) }
            if visibleSettingsWindow != nil {
                // AppKit may hide the app while its Dock presence changes.
                // Restore the existing window after the activation transition finishes.
                bringSettingsToFront()
            }
        }
        guard let image = NSImage(named: NSImage.Name(dockIcon.color.assetName)) else { return }
        application.applicationIconImage = image
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
        if hasStartedHistory { store.resumeMonitoring() }
        shortcuts.start()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard let panel, panel.isVisible, !panel.isOnActiveSpace else { return }
        // Changing Spaces need not resign the panel's borrowed keyboard focus.
        hidePanel(restorePreviousApplication: false)
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
        guard let window = notification.object as? NSWindow else { return }
        if window === statisticsWindow {
            statisticsWindow = nil
            return
        }
        guard window === settingsWindow else { return }
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

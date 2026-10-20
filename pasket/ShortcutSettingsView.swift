import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var shortcuts: GlobalShortcutManager
    @Bindable var store: ClipboardStore
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Keyboard shortcuts")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("Click a shortcut to change it")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        historyShortcutCard
                        settingsShortcutCard
                        deletionShortcutCard
                    }

                    panelControls
                    folderAccessCard

                    if let error = shortcuts.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shortcutSettingsError")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            Divider().opacity(0.5)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text("Changes are saved automatically")
                Spacer()
                Text("Pasket")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 600, height: 520)
        .modifier(PasketSurface())
        .onExitCommand(perform: onClose)
        .sheet(isPresented: Binding(
            get: { shortcuts.isRecording },
            set: { if !$0 { shortcuts.cancelRecording() } }
        )) {
            recordingSheet
                .presentationBackground(.clear)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 16, weight: .medium))
                    Text("Make Pasket feel like second nature.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .padding(.vertical, 12)
            .overlay { WindowDragRegion() }
            .help("Drag the header to move Settings")
            .accessibilityIdentifier("settingsWindowDragArea")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14, height: 16)
            }
            .buttonStyle(PasketButtonStyle())
            .keyboardShortcut("w", modifiers: .command)
            .help("Close Settings (Esc)")
            .accessibilityLabel("Close settings")
        }
        .padding(.trailing, 14)
    }

    private var historyShortcutCard: some View {
        VStack(spacing: 0) {
            shortcutRow(
                title: "Show Clipboard History",
                description: "Bring your basket into view from any app.",
                symbol: "basket",
                shortcut: shortcuts.shortcut,
                action: .showHistory
            )
            Divider().opacity(0.35)
            HStack {
                Label("Global · Default: Hyper + P", systemImage: "globe")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Default") { shortcuts.restoreDefault() }
                    .buttonStyle(PasketButtonStyle())
                    .disabled(shortcuts.shortcut == .default)
            }
            .font(.system(size: 12))
            .padding(.leading, 12)
            .padding(.trailing, 3)
            .padding(.vertical, 4)
        }
        .modifier(SettingsCard())
    }

    private var settingsShortcutCard: some View {
        VStack(spacing: 0) {
            shortcutRow(
                title: "Open Settings",
                description: "Open Settings from your clipboard history.",
                symbol: "gearshape",
                shortcut: shortcuts.settingsShortcut,
                action: .openSettings
            )
            Divider().opacity(0.35)
            HStack {
                Label("History panel only · Default: ⌘,", systemImage: "rectangle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { shortcuts.setSettingsShortcut(nil) }
                    .buttonStyle(PasketButtonStyle())
                    .disabled(shortcuts.settingsShortcut == nil)
                Button("Restore Default") { shortcuts.setSettingsShortcut(.defaultSettings) }
                    .buttonStyle(PasketButtonStyle())
                    .disabled(shortcuts.settingsShortcut == .defaultSettings)
            }
            .font(.system(size: 12))
            .padding(.leading, 12)
            .padding(.trailing, 3)
            .padding(.vertical, 4)
        }
        .modifier(SettingsCard())
    }

    private var deletionShortcutCard: some View {
        VStack(spacing: 0) {
            shortcutRow(
                title: "Delete Selected Item",
                description: "Remove the selected entry from your history.",
                symbol: "trash",
                shortcut: shortcuts.deletionShortcut,
                action: .deleteSelectedItem
            )
            Divider().opacity(0.35)
            HStack {
                Label("History panel only · Optional", systemImage: "rectangle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { shortcuts.setDeletionShortcut(nil) }
                    .buttonStyle(PasketButtonStyle())
                    .disabled(shortcuts.deletionShortcut == nil)
            }
            .font(.system(size: 12))
            .padding(.leading, 12)
            .padding(.trailing, 3)
            .padding(.vertical, 4)
        }
        .modifier(SettingsCard())
    }

    private func shortcutRow(
        title: String, description: String, symbol: String,
        shortcut: GlobalShortcut?, action: GlobalShortcutManager.RecordingAction
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button { shortcuts.beginRecording(action) } label: {
                if let shortcut {
                    ShortcutKeycaps(shortcut: shortcut)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Set Shortcut")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 22)
                }
            }
            .buttonStyle(PasketButtonStyle())
            .fixedSize()
            .help("Record a shortcut for \(title)")
            .accessibilityLabel("Record \(title) shortcut")
            .accessibilityValue(shortcut?.displayName ?? "Not set")
        }
        .padding(12)
    }

    private var panelControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In the history panel")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                panelControl(keys: "↑ ↓", title: "Navigate")
                panelControl(keys: "↩", title: "Copy & return")
                panelControl(keys: "esc", title: "Dismiss")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .modifier(SettingsCard())
    }

    private var folderAccessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File access")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Authorize Folder…") { store.authorizeFolder() }
                    .buttonStyle(PasketButtonStyle())
            }
            Text("Allow read-only access once for current and future files in a folder and its subfolders. Files stay in place; no copies are saved.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(store.authorizedFolders, id: \.path) { folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder.name).font(.system(size: 13, weight: .medium))
                        Text(folder.path)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.path)
                    }
                    Spacer()
                    Button("Remove") { Task { await store.removeAuthorizedFolder(folder.path) } }
                        .buttonStyle(PasketButtonStyle())
                        .accessibilityLabel("Remove folder access for \(folder.name)")
                }
            }
            if let error = store.folderAccessError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .modifier(SettingsCard())
        .disabled(store.isDebugMode || store.isStorageBlocked || store.isLoading)
    }

    private func panelControl(keys: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var recordingSheet: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Record a shortcut")
                    .font(.system(size: 16, weight: .medium))
                Text(shortcuts.recordingAction.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("Press your new key combination")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            Text("Include Command, Control, or Option and another key.\nYour shortcut is saved as soon as it is accepted.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = shortcuts.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ShortcutEventMonitor { event in
                shortcuts.record(event)
                return true
            }
                .frame(height: 1)
                .accessibilityHidden(true)
            Button { shortcuts.cancelRecording() } label: {
                HStack(spacing: 8) {
                    Text("Cancel")
                    Text("esc").foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(PasketButtonStyle())
        }
        .padding(20)
        .frame(width: 380)
        .modifier(PasketSurface())
        .interactiveDismissDisabled()
    }
}

private struct SettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ShortcutKeycaps: View {
    let shortcut: GlobalShortcut

    private var keys: [String] {
        let modifiers = String(shortcut.displayName.dropLast(shortcut.keyLabel.count))
        return modifiers.map(String.init) + [shortcut.keyLabel]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 12)
                    .padding(.horizontal, 5)
                    .frame(height: 22)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.primary.opacity(0.08))
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.displayName)
    }
}

struct ShortcutEventMonitor: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: CaptureView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class CaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      window.attachedSheet == nil, event.window === window else { return event }
                return self.onKeyDown?(event) == true ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

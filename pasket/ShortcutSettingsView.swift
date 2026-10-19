import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var shortcuts: GlobalShortcutManager
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("KEYBOARD SHORTCUTS")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.8)
                        Spacer()
                        Text("Click a shortcut to change it")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        historyShortcutCard
                        deletionShortcutCard
                    }

                    panelControls

                    if let error = shortcuts.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shortcutSettingsError")
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.5)
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                Text("Changes are saved automatically")
                Spacer()
                Text("Pasket")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
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
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 18, weight: .medium))
                Text("Make Pasket feel like second nature.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            WindowDragHandle()
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
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
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
        .modifier(SettingsCard())
    }

    private func shortcutRow(
        title: String, description: String, symbol: String,
        shortcut: GlobalShortcut?, action: GlobalShortcutManager.RecordingAction
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Button { shortcuts.beginRecording(action) } label: {
                if let shortcut {
                    ShortcutKeycaps(shortcut: shortcut)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Set Shortcut")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 28)
                }
            }
            .buttonStyle(PasketButtonStyle())
            .fixedSize()
            .help("Record a shortcut for \(title)")
            .accessibilityLabel("Record \(title) shortcut")
            .accessibilityValue(shortcut?.displayName ?? "Not set")
        }
        .padding(14)
    }

    private var panelControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IN THE HISTORY PANEL")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            HStack(spacing: 22) {
                panelControl(keys: "↑ ↓", title: "Navigate")
                panelControl(keys: "↩", title: "Copy & return")
                panelControl(keys: "esc", title: "Dismiss")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    private func panelControl(keys: String, title: String) -> some View {
        HStack(spacing: 7) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 7)
                .frame(height: 23)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var recordingSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 7) {
                Text("Record a shortcut")
                    .font(.system(size: 18, weight: .medium))
                Text(shortcuts.recordingAction == .deleteSelectedItem
                     ? "Delete Selected Item" : "Show Clipboard History")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text("Press your new key combination")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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
                HStack(spacing: 10) {
                    Text("Cancel")
                    Text("esc").foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(PasketButtonStyle())
        }
        .padding(24)
        .frame(width: 380)
        .modifier(PasketSurface())
        .interactiveDismissDisabled()
    }
}

private struct SettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.2))
                    .allowsHitTesting(false)
            }
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
                    .frame(height: 28)
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

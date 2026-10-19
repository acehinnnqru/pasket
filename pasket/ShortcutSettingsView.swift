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
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("KEYBOARD SHORTCUTS")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1.3)
                        Spacer()
                        Text("Click a shortcut to change it")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
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
                .padding(26)
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
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
        }
        .frame(width: 660, height: 600)
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
        HStack(spacing: 14) {
            Image(systemName: "gearshape")
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 23, weight: .medium))
                Text("Make Pasket feel like second nature.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2)))
            }
            .buttonStyle(SettingsControlStyle())
            .keyboardShortcut("w", modifiers: .command)
            .help("Close Settings (Esc)")
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
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
                    .buttonStyle(SettingsControlStyle())
                    .disabled(shortcuts.shortcut == .default)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
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
                    .buttonStyle(SettingsControlStyle())
                    .disabled(shortcuts.deletionShortcut == nil)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
        .modifier(SettingsCard())
    }

    private func shortcutRow(
        title: String, description: String, symbol: String,
        shortcut: GlobalShortcut?, action: GlobalShortcutManager.RecordingAction
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
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
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(.primary.opacity(0.04), in: Capsule())
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                }
            }
            .buttonStyle(SettingsControlStyle())
            .fixedSize()
            .help("Record a shortcut for \(title)")
            .accessibilityLabel("Record \(title) shortcut")
            .accessibilityValue(shortcut?.displayName ?? "Not set")
        }
        .padding(18)
    }

    private var panelControls: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
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
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            VStack(spacing: 7) {
                Text("Record a shortcut")
                    .font(.system(size: 21, weight: .medium))
                Text(shortcuts.recordingAction == .deleteSelectedItem
                     ? "Delete Selected Item" : "Show Clipboard History")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text("Press your new key combination")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
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
                HStack(spacing: 16) {
                    Text("Cancel")
                    Text("esc").foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
            }
            .buttonStyle(SettingsControlStyle())
        }
        .padding(28)
        .frame(width: 420)
        .modifier(PasketSurface(cornerRadius: 26))
        .interactiveDismissDisabled()
    }
}

private struct SettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.2))
                    .allowsHitTesting(false)
            }
    }
}

private struct SettingsControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
            .brightness(isEnabled && isHovered ? 0.08 : 0)
            .onHover { isHovered = $0 }
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
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .frame(minWidth: 16)
                    .padding(.horizontal, 6)
                    .frame(height: 32)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
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

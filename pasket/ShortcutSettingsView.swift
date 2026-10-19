import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var shortcuts: GlobalShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard Shortcuts").font(.title2.weight(.medium))
                Text("Open history from any app and manage items in the history panel.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Show Clipboard History")
                Spacer()
                Button {
                    shortcuts.beginRecording()
                } label: {
                    Text(shortcuts.shortcut.displayName)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .help("Record a new shortcut")
                .accessibilityLabel("Record shortcut, currently \(shortcuts.shortcut.displayName)")
            }

            HStack {
                Text("Default: Hyper + P (⌃⌥⇧⌘P)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Default") { shortcuts.restoreDefault() }
            }

            Divider()

            HStack {
                Text("Delete Selected Item")
                Spacer()
                Button {
                    shortcuts.beginRecording(.deleteSelectedItem)
                } label: {
                    Text(shortcuts.deletionShortcut?.displayName ?? "Not Set")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .help("Record a shortcut for deleting the selected item")
                .accessibilityLabel("Record delete shortcut, currently \(shortcuts.deletionShortcut?.displayName ?? "not set")")
                Button("Clear") { shortcuts.setDeletionShortcut(nil) }
                    .disabled(shortcuts.deletionShortcut == nil)
            }
            Text("Only active in the history panel. No shortcut is assigned by default.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = shortcuts.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 540, height: 420)
        .sheet(isPresented: Binding(
            get: { shortcuts.isRecording },
            set: { if !$0 { shortcuts.cancelRecording() } }
        )) {
            recordingSheet
        }
    }

    private var recordingSheet: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(shortcuts.recordingAction == .deleteSelectedItem
                 ? "Shortcut for Delete Selected Item" : "Shortcut for Show Clipboard History")
                .font(.title3.weight(.medium))
            Text("Use Command, Control, or Option with another key.\nPress Escape to cancel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = shortcuts.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ShortcutEventMonitor { event in
                shortcuts.record(event)
                return true
            }
                .frame(height: 1)
                .accessibilityHidden(true)
            Button("Cancel") { shortcuts.cancelRecording() }
        }
        .padding(28)
        .frame(width: 420)
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

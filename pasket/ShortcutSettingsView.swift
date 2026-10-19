import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var shortcuts: GlobalShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard Shortcut").font(.title2.weight(.medium))
                Text("Open your clipboard history from any app.")
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

            if let error = shortcuts.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 480, height: 300)
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
            Text("Press a new shortcut").font(.title3.weight(.medium))
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
            ShortcutCaptureView(onKeyDown: shortcuts.record)
                .frame(height: 1)
                .accessibilityHidden(true)
            Button("Cancel") { shortcuts.cancelRecording() }
        }
        .padding(28)
        .frame(width: 420)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

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
        var onKeyDown: ((NSEvent) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                self.onKeyDown?(event)
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

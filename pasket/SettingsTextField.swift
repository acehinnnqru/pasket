import AppKit
import SwiftUI

// SwiftUI TextField supplies its own TextKit 2 editor and bypasses the window's
// field-editor delegate. Use a native field so SettingsFieldEditor handles editing.
struct SettingsTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var label: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TextField {
        let field = TextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .right
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.parent.isFocused = true
        }
        field.setAccessibilityLabel(label)
        return field
    }

    func updateNSView(_ field: TextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.setAccessibilityLabel(label)
        // Do not replace the field editor's text during a binding update: doing so
        // resets the selection while typing or dragging over digits.
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.updateFocus(for: field)
    }

    static func dismantleNSView(_ field: TextField, coordinator: Coordinator) {
        coordinator.focusUpdate?.cancel()
        field.delegate = nil
        field.onFocus = nil
    }

    final class TextField: NSTextField {
        var onFocus: (() -> Void)?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            // AppKit's begin-editing notification waits for the first text change;
            // clicks and keyboard navigation must update focus before that happens.
            if accepted { onFocus?() }
            return accepted
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsTextField
        var focusUpdate: Task<Void, Never>?

        init(_ parent: SettingsTextField) { self.parent = parent }

        func updateFocus(for field: NSTextField) {
            focusUpdate?.cancel()
            let shouldFocus = parent.isFocused && field.isEnabled
            guard (field.currentEditor() != nil) != shouldFocus else { return }
            // SwiftUI can update several fields during one focus transfer. Let that
            // update finish before changing AppKit's first responder.
            focusUpdate = Task { @MainActor [weak self, weak field] in
                await Task.yield()
                guard !Task.isCancelled, let self, let field, let window = field.window else { return }
                if parent.isFocused && field.isEnabled {
                    if field.currentEditor() == nil { window.makeFirstResponder(field) }
                } else if field.currentEditor() != nil {
                    window.makeFirstResponder(nil)
                }
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            control.window?.makeFirstResponder(nil)
            parent.isFocused = false
            return true
        }
    }
}

import AppKit

@MainActor
final class SettingsFieldEditor {
    private var editor: NSTextView?

    func editor(for client: Any?) -> NSTextView? {
        guard let field = client as? NSTextField, field.isEditable, !(field is NSSecureTextField) else { return nil }
        if let editor { return editor }
        // A hang sample on macOS 26 showed the shared TextKit 2 field editor spinning
        // in mouse selection while switching settings inputs. Scope this workaround to Settings.
        let editor = NSTextView(usingTextLayoutManager: false)
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        self.editor = editor
        return editor
    }
}

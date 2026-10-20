import AppKit
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct SettingsFieldEditorTests {
    @Test func ordinaryInputsShareALegacyEditorButLabelsAndSecureFieldsDoNot() throws {
        let provider = SettingsFieldEditor()
        let first = NSTextField(string: "60")
        let second = NSTextField(string: "2026")
        let editor = try #require(provider.editor(for: first))
        #expect(editor.isFieldEditor)
        #expect(editor.textLayoutManager == nil)
        #expect(provider.editor(for: second) === editor)
        #expect(provider.editor(for: NSTextField(labelWithString: "days")) == nil)
        #expect(provider.editor(for: NSSecureTextField(string: "")) == nil)
        #expect(provider.editor(for: nil) == nil)
    }

    @Test func switchingInputsCommitsEditsWithoutEnteringTextKit2() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let delegate = EditorWindowDelegate()
        window.delegate = delegate
        let fields = ["60", "2026", "50", "500"].enumerated().map { index, value in
            let field = NSTextField(string: value)
            field.frame = NSRect(x: 20, y: 20 + index * 30, width: 100, height: 24)
            window.contentView?.addSubview(field)
            return field
        }
        for index in 0..<24 {
            let field = fields[index % fields.count]
            #expect(window.makeFirstResponder(field))
            if index > 0 {
                #expect(fields[(index - 1) % fields.count].stringValue == String(index + 99))
            }
            let editor = try #require(field.currentEditor() as? NSTextView)
            #expect(editor.textLayoutManager == nil)
            editor.string = String(index + 100)
            editor.didChangeText()
        }
        #expect(window.makeFirstResponder(nil))
        #expect(fields[23 % fields.count].stringValue == "123")
    }
}

@MainActor private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    private let provider = SettingsFieldEditor()

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        provider.editor(for: client)
    }
}

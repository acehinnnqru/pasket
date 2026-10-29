import AppKit
import Observation
import SwiftUI
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

    @Test func hostedInputsUseTheLegacyEditorAndRemainRecognizableToClickDismissal() async throws {
        _ = NSApplication.shared
        let model = HostedSettingsInputs()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let delegate = EditorWindowDelegate()
        window.delegate = delegate
        let hosting = NSHostingView(rootView: HostedSettingsInputsView(model: model))
        window.contentView = hosting
        await settle(hosting)

        let fields = editableFields(in: hosting)
        #expect(fields.count == model.values.count)
        for field in fields {
            #expect(!field.isBordered)
            #expect(!field.isBezeled)
            #expect(!field.drawsBackground)
            #expect(field.alignment == .right)
            #expect(field.font == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        }
        for index in 0..<12 {
            for field in fields {
                let point = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: hosting)
                #expect(hitsEditableInput(hosting.hitTest(point)))
            }
            model.focus = index % model.values.count
            await settle(hosting)
            let editor = try #require(window.firstResponder as? NSTextView)
            #expect(editor.isFieldEditor)
            #expect(editor.textLayoutManager == nil)
            #expect(delegate.editableClientRequests > 0)

            let field = try #require(fields.first { $0.currentEditor() === editor })
            let point = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: hosting)
            #expect(hitsEditableInput(hosting.hitTest(point)))
            editor.string = String(index + 100)
            let selection = NSRange(location: 1, length: 1)
            editor.setSelectedRange(selection)
            editor.didChangeText()
            await settle(hosting)
            #expect(model.values[index % model.values.count] == String(index + 100))
            #expect(editor.selectedRange() == selection)
        }
        model.focus = nil
        await settle(hosting)
        #expect(!(window.firstResponder is NSTextView))

        for index in 0..<12 {
            let input = index % model.values.count
            let field = try #require(fields.first { $0.stringValue == model.values[input] })
            #expect(window.makeFirstResponder(field))
            await settle(hosting)
            #expect(model.focus == input)
            let editor = try #require(field.currentEditor() as? NSTextView)
            #expect(editor.textLayoutManager == nil)
        }

        let focused = try #require(model.focus)
        let field = try #require(fields.first { $0.stringValue == model.values[focused] })
        let editor = try #require(field.currentEditor() as? NSTextView)
        model.values[focused] = "9999"
        await settle(hosting)
        #expect(field.stringValue == "9999")
        #expect(editor.string == "9999")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await settle(hosting)
        #expect(model.focus == nil)
        #expect(field.currentEditor() == nil)

        model.focus = focused
        await settle(hosting)
        model.disabledIndex = focused
        await settle(hosting)
        #expect(!field.isEnabled)
        #expect(field.currentEditor() == nil)
        model.focus = focused
        await settle(hosting)
        #expect(field.currentEditor() == nil)
        model.disabledIndex = nil
        model.focus = nil
        await settle(hosting)

        let orderedFields = try model.values.map { value in
            try #require(fields.first { $0.stringValue == value })
        }
        for index in orderedFields.indices {
            orderedFields[index].nextKeyView = orderedFields[(index + 1) % orderedFields.count]
        }
        model.focus = 0
        await settle(hosting)
        let firstEditor = try #require(orderedFields[0].currentEditor() as? NSTextView)
        firstEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        await settle(hosting)
        #expect(model.focus == 1)
        let secondEditor = try #require(orderedFields[1].currentEditor() as? NSTextView)
        secondEditor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        await settle(hosting)
        #expect(model.focus == 0)

        #expect(window.makeFirstResponder(orderedFields[2]))
        await settle(hosting)
        #expect(model.focus == 2)
        #expect(window.makeFirstResponder(nil))
        await settle(hosting)
        #expect(model.focus == nil)
        #expect(orderedFields[2].currentEditor() == nil)
    }

    private func editableFields(in view: NSView) -> [NSTextField] {
        let fields = view.subviews.flatMap { editableFields(in: $0) }
        guard let field = view as? NSTextField, field.isEditable else { return fields }
        return [field] + fields
    }

    private func hitsEditableInput(_ view: NSView?) -> Bool {
        var current = view
        while let view = current {
            if let field = view as? NSTextField, field.isEditable { return true }
            if let editor = view as? NSTextView, editor.isEditable { return true }
            current = view.superview
        }
        return false
    }

    private func settle(_ view: NSView) async {
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    private let provider = SettingsFieldEditor()
    private(set) var editableClientRequests = 0

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if let field = client as? NSTextField, field.isEditable { editableClientRequests += 1 }
        return provider.editor(for: client)
    }
}

@MainActor @Observable private final class HostedSettingsInputs {
    var values = ["60", "2026", "50", "500"]
    var focus: Int?
    var disabledIndex: Int?
}

private struct HostedSettingsInputsView: View {
    let model: HostedSettingsInputs

    var body: some View {
        VStack {
            ForEach(model.values.indices, id: \.self) { index in
                SettingsTextField(
                    text: Binding(get: { model.values[index] }, set: { model.values[index] = $0 }),
                    isFocused: Binding(get: { model.focus == index }, set: { focused in
                        if focused { model.focus = index }
                        else if model.focus == index { model.focus = nil }
                    }),
                    label: "History limit \(index)"
                )
                .frame(width: 108, height: 26)
                .disabled(model.disabledIndex == index)
            }
        }
    }
}

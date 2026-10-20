import AppKit
import Carbon
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var shortcuts: GlobalShortcutManager
    @Bindable var store: ClipboardStore
    var onClose: () -> Void = {}
    @FocusState private var focusedHistoryField: HistoryLimitField?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    keyboardShortcutsSection
                    HistoryRetentionSettingsView(store: store, focusedField: $focusedHistoryField)

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
                Text("Shortcuts save automatically.")
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
        .background {
            SettingsFocusDismissal { focusedHistoryField = nil }
        }
        .background {
            ShortcutEventMonitor { event in
                guard !shortcuts.isRecording, event.keyCode == UInt16(kVK_Escape),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return false }
                if !event.isARepeat { onClose() }
                return true
            }
        }
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

    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Keyboard shortcuts")
            VStack(spacing: 0) {
                shortcutRow(
                    title: "Show Clipboard History",
                    description: "Global · Available in any app",
                    symbol: "basket",
                    shortcut: shortcuts.shortcut,
                    action: .showHistory
                )
                Divider().opacity(0.35).padding(.leading, 40)
                shortcutRow(
                    title: "Open Settings",
                    description: "History panel only",
                    symbol: "gearshape",
                    shortcut: shortcuts.settingsShortcut,
                    action: .openSettings
                )
                Divider().opacity(0.35).padding(.leading, 40)
                shortcutRow(
                    title: "Delete Selected Item",
                    description: "History panel only · Optional",
                    symbol: "trash",
                    shortcut: shortcuts.deletionShortcut,
                    action: .deleteSelectedItem
                )
            }
            .modifier(SettingsCard())
            Text("Click a shortcut to change it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            panelControls
        }
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
            if action != .deleteSelectedItem {
                let defaultShortcut: GlobalShortcut = action == .showHistory ? .default : .defaultSettings
                Button {
                    if action == .showHistory {
                        shortcuts.restoreDefault()
                    } else {
                        shortcuts.setSettingsShortcut(.defaultSettings)
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 14, height: 16)
                }
                .buttonStyle(PasketButtonStyle())
                .disabled(shortcut == defaultShortcut)
                .help(action == .showHistory ? "Restore Default (Hyper + P)" : "Restore Default (⌘,)")
                .accessibilityLabel("Restore \(title) shortcut to default")
            } else {
                Color.clear
                    .frame(width: 32, height: 28)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
    }

    private var panelControls: some View {
        HStack(spacing: 12) {
            Text("In history:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            panelControl(keys: "↑ ↓", title: "Navigate")
            panelControl(keys: "↩", title: "Paste & return")
            panelControl(keys: "esc", title: "Dismiss")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func panelControl(keys: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.system(size: 11))
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
            HStack {
                if shortcuts.recordingAction != .showHistory {
                    Button("Clear Shortcut", role: .destructive) {
                        if shortcuts.recordingAction == .openSettings {
                            shortcuts.setSettingsShortcut(nil)
                        } else {
                            shortcuts.setDeletionShortcut(nil)
                        }
                        shortcuts.cancelRecording()
                    }
                    .disabled(shortcuts.recordingAction == .openSettings
                              ? shortcuts.settingsShortcut == nil : shortcuts.deletionShortcut == nil)
                    .accessibilityLabel("Clear \(shortcuts.recordingAction.title) shortcut")
                }
                Spacer()
                Button { shortcuts.cancelRecording() } label: {
                    HStack(spacing: 8) {
                        Text("Cancel")
                        Text("esc").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(PasketButtonStyle())
        }
        .padding(20)
        .frame(width: 380)
        .modifier(PasketSurface())
        .interactiveDismissDisabled()
    }
}

private struct HistoryRetentionSettingsView: View {
    @Bindable var store: ClipboardStore
    var focusedField: FocusState<HistoryLimitField?>.Binding
    @State private var draft = HistoryRetentionDraft(.default)
    @State private var confirmation: ClipboardRetentionPlan?
    @State private var impactChanged = false

    private var canApply: Bool {
        guard let settings = draft.settings else { return false }
        return store.needsRetentionReview || settings != store.retentionSettings
    }

    private var hasChanges: Bool {
        store.needsRetentionReview || draft.settings != store.retentionSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "History", showsUnsavedChanges: hasChanges)
            VStack(alignment: .leading, spacing: 0) {
                if store.needsRetentionReview {
                    Label("Review and apply your history limits to enable automatic cleanup. Existing history has been kept.",
                          systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                    Divider().opacity(0.35).padding(.horizontal, 12)
                }
                limitRow("Keep history for", detail: "Since the last copy", value: $draft.days, unit: "days", field: .days)
                Divider().opacity(0.35).padding(.horizontal, 12)
                limitRow("Maximum records", detail: "\(store.totalCount.formatted()) entries stored",
                         value: $draft.items, unit: "entries", field: .items)
                Divider().opacity(0.35).padding(.horizontal, 12)
                limitRow("Text storage", detail: "\(Self.formatBytes(store.textStorageBytes)) used · includes links and email",
                         value: $draft.text, unit: "MiB", field: .text)
                Divider().opacity(0.35).padding(.horizontal, 12)
                limitRow("Image storage", detail: "\(Self.formatBytes(store.imageStorageBytes)) used · includes thumbnails",
                         value: $draft.images, unit: "MiB", field: .images)
                Divider().opacity(0.35)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apply to save these limits. The oldest matching entries are cleaned up first. Original files stay untouched.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let settings = draft.settings, settings.maximumItems == nil, settings.maximumTextBytes == nil,
                       settings.maximumImageBytes == nil, settings.maximumAgeDays == nil {
                        Text("All limits are Unlimited. History may continue to grow.")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    if draft.settings == nil {
                        Text("Enter positive whole numbers, or choose Unlimited.")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    if let error = store.retentionError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Restore Defaults") {
                            focusedField.wrappedValue = nil
                            draft = HistoryRetentionDraft(.default)
                        }
                            .buttonStyle(PasketButtonStyle())
                        Spacer()
                        if store.isApplyingRetention { ProgressView().controlSize(.small) }
                        Button("Apply") { apply() }
                            .buttonStyle(HistoryApplyButtonStyle())
                            .disabled(!canApply)
                            .accessibilityIdentifier("applyHistoryLimits")
                    }
                }
                .padding(12)
            }
            .modifier(SettingsCard())
        }
        .disabled(store.isDebugMode || store.isStorageBlocked || store.isLoading || store.isApplyingRetention)
        .onAppear { draft = HistoryRetentionDraft(store.retentionSettings) }
        .onChange(of: store.isLoading) {
            if !store.isLoading { draft = HistoryRetentionDraft(store.retentionSettings) }
        }
        .sheet(isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            if let plan = confirmation {
                confirmationSheet(plan)
                    .presentationBackground(.clear)
            }
        }
    }

    nonisolated private static func formatBytes(_ bytes: Int) -> String {
        let mib = Double(bytes) / Double(ClipboardRetention.mebibyte)
        if bytes > 0, mib < 0.1 { return "\(bytes.formatted()) B" }
        return "\(mib.formatted(.number.precision(.fractionLength(0...1)))) MiB"
    }

    private func limitRow(_ title: String, detail: String, value: Binding<HistoryLimitDraft>,
                          unit: String, field: HistoryLimitField) -> some View {
        let isFocused = focusedField.wrappedValue == field
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                TextField("", text: value.number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused(focusedField, equals: field)
                    .onSubmit { focusedField.wrappedValue = nil }
                    .accessibilityLabel(title)
                Button { focusedField.wrappedValue = field } label: {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Edit \(title.lowercased())")
            }
            .padding(.horizontal, 10)
            .frame(width: 118, height: 34)
            .background {
                Button { focusedField.wrappedValue = field } label: {
                    RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.035))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1))
                    .allowsHitTesting(false)
            }
            .opacity(value.wrappedValue.unlimited ? 0.35 : 1)
            .disabled(value.wrappedValue.unlimited)
            Toggle("Unlimited", isOn: value.unlimited)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .frame(width: 88, alignment: .leading)
                .accessibilityLabel("Unlimited \(title.lowercased())")
                .onChange(of: value.wrappedValue.unlimited) {
                    if focusedField.wrappedValue == field { focusedField.wrappedValue = nil }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func confirmationSheet(_ plan: ClipboardRetentionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Apply history limits?", systemImage: "trash")
                .font(.system(size: 16, weight: .medium))
            if impactChanged {
                Text("History changed while this confirmation was open. Review the updated cleanup before applying.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            Text("These settings will delete \(Text(plan.count.formatted()).bold().foregroundStyle(Color.accentColor)) history \(plan.count == 1 ? "entry" : "entries") and free approximately \(Text(Self.formatBytes(plan.estimatedBytes)).bold().foregroundStyle(Color.accentColor)) of storage.")
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("historyCleanupImpact")
            Text("This cannot be undone. Original files and your current clipboard will remain untouched. Space is estimated from saved records and images; database overhead may differ.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = store.retentionError {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { confirmation = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Apply and Delete", role: .destructive) { apply(confirmed: plan) }
                    .accessibilityIdentifier("confirmHistoryCleanup")
            }
            .buttonStyle(PasketButtonStyle())
            .disabled(store.isApplyingRetention)
        }
        .padding(22)
        .frame(width: 420)
        .modifier(PasketSurface())
        .interactiveDismissDisabled()
    }

    private func apply(confirmed: ClipboardRetentionPlan? = nil) {
        guard let settings = draft.settings else { return }
        focusedField.wrappedValue = nil
        Task {
            if let plan = await store.applyRetention(settings, confirmed: confirmed) {
                impactChanged = confirmed != nil
                confirmation = plan
            } else if store.retentionError == nil {
                confirmation = nil
                draft = HistoryRetentionDraft(store.retentionSettings)
            }
        }
    }
}

private enum HistoryLimitField: Hashable {
    case days, items, text, images
}

private struct HistoryApplyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(isEnabled ? Color.accentColor : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed && isEnabled ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

// Observe mouse clicks without consuming them or interfering with selection inside an input.
private struct SettingsFocusDismissal: NSViewRepresentable {
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> ClickObserver {
        let view = ClickObserver()
        view.onDismiss = onDismiss
        return view
    }

    func updateNSView(_ nsView: ClickObserver, context: Context) {
        nsView.onDismiss = onDismiss
    }

    static func dismantleNSView(_ nsView: ClickObserver, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class ClickObserver: NSView {
        var onDismiss: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.attachedSheet == nil, let content = window.contentView else { return event }
                var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
                while let view = hit {
                    if let field = view as? NSTextField, field.isEditable { return event }
                    if let editor = view as? NSTextView, editor.isEditable { return event }
                    hit = view.superview
                }
                self.onDismiss?()
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct HistoryLimitDraft {
    var number: String
    var unlimited: Bool

    init(_ value: Int?, unit: Int = 1) {
        number = String((value ?? unit) / unit)
        unlimited = value == nil
    }

    var isValid: Bool {
        unlimited || (!number.isEmpty && number.allSatisfy(\.isNumber)
                      && Int(number).map { $0 > 0 && $0 <= Int.max / ClipboardRetention.mebibyte } == true)
    }

    func value(unit: Int = 1) -> Int? {
        unlimited ? nil : Int(number).map { $0 * unit }
    }
}

private struct HistoryRetentionDraft {
    var days: HistoryLimitDraft
    var items: HistoryLimitDraft
    var text: HistoryLimitDraft
    var images: HistoryLimitDraft

    init(_ settings: ClipboardRetention) {
        days = HistoryLimitDraft(settings.maximumAgeDays)
        items = HistoryLimitDraft(settings.maximumItems)
        text = HistoryLimitDraft(settings.maximumTextBytes, unit: ClipboardRetention.mebibyte)
        images = HistoryLimitDraft(settings.maximumImageBytes, unit: ClipboardRetention.mebibyte)
    }

    var settings: ClipboardRetention? {
        guard [days, items, text, images].allSatisfy(\.isValid) else { return nil }
        let settings = ClipboardRetention(maximumItems: items.value(),
                                          maximumTextBytes: text.value(unit: ClipboardRetention.mebibyte),
                                          maximumImageBytes: images.value(unit: ClipboardRetention.mebibyte),
                                          maximumAgeDays: days.value())
        return settings.isValid ? settings : nil
    }
}

private struct SettingsSectionHeader: View {
    let title: String
    var showsUnsavedChanges = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if showsUnsavedChanges {
                Text("Unsaved changes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("historyLimitsUnsaved")
            }
        }
        .padding(.horizontal, 2)
        .accessibilityAddTraits(.isHeader)
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

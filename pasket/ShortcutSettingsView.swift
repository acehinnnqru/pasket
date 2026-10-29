import AppKit
import Carbon
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var shortcuts: GlobalShortcutManager
    @Bindable var store: ClipboardStore
    @Bindable var dockIcon: DockIconPreferences
    @Bindable var accentColor: AccentColorPreferences
    @Bindable var appearance: AppearancePreferences
    @Bindable var loginItem: LoginItemPreferences
    var onClose: () -> Void = {}
    @State private var focusedHistoryField: HistoryLimitField?
    @State private var presentedPicker: SettingsPicker?

    private enum SettingsPicker: Equatable {
        case typeFilter, appearance
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    generalSection
                    keyboardShortcutsSection
                    historyPanelSection
                    HistoryRetentionSettingsView(store: store, focusedField: $focusedHistoryField)

                    if let error = shortcuts.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shortcutSettingsError")
                    }

                    appearanceSection
                    accentColorSection
                    dockIconSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .controlSize(.small)
            }
            Divider().opacity(0.5)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text("Shortcuts save only after confirmation.")
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
        .modifier(PasketPickerOverlay())
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .background {
            SettingsFocusDismissal { focusedHistoryField = nil }
        }
        .background {
            ShortcutEventMonitor { event in
                guard !shortcuts.isRecording, event.keyCode == UInt16(kVK_Escape),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return false }
                if !event.isARepeat {
                    if presentedPicker != nil { presentedPicker = nil }
                    else { onClose() }
                }
                return true
            }
        }
        .sheet(isPresented: Binding(
            get: { shortcuts.isRecording },
            set: { if !$0 { shortcuts.cancelRecording() } }
        )) {
            ShortcutRecordingView(shortcuts: shortcuts)
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
            .overlay { PasketWindowDragRegion() }
            .help("Drag the header to move Settings")
            .accessibilityIdentifier("settingsWindowDragArea")
            PasketCloseButton(title: "Close settings", help: "Close Settings (Esc)", action: onClose)
            .keyboardShortcut("w", modifiers: .command)
        }
        .padding(.trailing, 14)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "General")
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    title: "Start at Login",
                    detail: "Automatically start Pasket when you log in to your Mac.",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ),
                    accessibilityIdentifier: "startAtLogin"
                )
                if loginItem.requiresApproval {
                    Text("Allow Pasket in System Settings to enable Start at Login.")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings…") { loginItem.openSystemSettings() }
                        .buttonStyle(PasketButtonStyle())
                }
                if let error = loginItem.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("startAtLoginError")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .modifier(SettingsCard())
        }
    }

    private var historyPanelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "History panel")
            VStack(alignment: .leading, spacing: 12) {
                SettingsControlRow(title: "Remember type filter", detail: store.filterPreferences.memory.explanation) {
                    PasketPicker(title: "Remember type filter", selection: Binding<ClipboardFilterMemory>(
                        get: { store.filterPreferences.memory },
                        set: { store.filterPreferences.select($0) }
                    ), isPresented: pickerPresentation(.typeFilter), options: ClipboardFilterMemory.allCases) { memory in
                        memory.title
                    }
                    .accessibilityIdentifier("clipboardFilterMemory")
                }
                Text("Default: 1 minute. Search text clears on each open. The type filter resets when Pasket quits.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .modifier(SettingsCard())
        }
    }

    private func pickerPresentation(_ picker: SettingsPicker) -> Binding<Bool> {
        Binding(
            get: { presentedPicker == picker },
            set: { isPresented in
                if isPresented { presentedPicker = picker }
                else if presentedPicker == picker { presentedPicker = nil }
            }
        )
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Appearance")
            SettingsControlRow(title: "Style", detail: appearance.appearance.explanation) {
                PasketPicker(title: "Appearance", selection: Binding<AppearanceOption>(
                    get: { appearance.appearance },
                    set: { appearance.select($0) }
                ), isPresented: pickerPresentation(.appearance), options: AppearanceOption.allCases) { option in
                    option.title
                }
                .accessibilityIdentifier("appearanceStyle")
            }
            .padding(12)
            .modifier(SettingsCard())
        }
    }

    private var accentColorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Accent color")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Color")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(accentColor.color.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    ForEach(AccentColorOption.allCases) { color in
                        Button { accentColor.select(color) } label: {
                            Circle()
                                .fill(color.tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(
                                    AngularGradient(colors: [.blue, .purple, .pink, .red, .orange, .yellow, .green, .blue],
                                                    center: .center)
                                ))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Circle().strokeBorder(.primary.opacity(0.12))
                                }
                                .padding(5)
                                .overlay {
                                    Circle().strokeBorder(accentColor.color == color ? Color.primary : .clear,
                                                          lineWidth: 2)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(AccentColorSwatchButtonStyle(isSelected: accentColor.color == color))
                        .help(color == .system ? "Follow the macOS accent color" : "Use \(color.title) accent color")
                        .accessibilityLabel("\(color.title) accent color")
                        .accessibilityAddTraits(accentColor.color == color ? [.isSelected] : [])
                        .accessibilityIdentifier("accentColor\(color.rawValue.capitalized)")
                        if color != AccentColorOption.allCases.last {
                            Spacer(minLength: 12)
                        }
                    }
                }
                Text("Used for selections, buttons, and the collection indicator. System follows your macOS accent color.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .modifier(SettingsCard())
        }
    }

    private var dockIconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Dock icon")
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    title: "Show in Dock",
                    detail: "Show Pasket in the Dock, even when Settings is closed. Changes take effect immediately.",
                    isOn: Binding(
                        get: { dockIcon.showInDock },
                        set: { dockIcon.setShowInDock($0) }
                    ),
                    accessibilityIdentifier: "showInDock"
                )
                Divider().opacity(0.35)
                HStack {
                    Text("Color")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(dockIcon.color.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(DockIconColor.allCases) { color in
                        Button { dockIcon.select(color) } label: {
                            VStack(spacing: 6) {
                                Image(color.assetName)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 64, height: 64)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .overlay {
                                        PasketShape.control
                                            .strokeBorder(dockIcon.color == color ? Color.accentColor : .clear,
                                                          lineWidth: 2)
                                    }
                                Text(color.title)
                                    .font(.system(size: 10, weight: dockIcon.color == color ? .medium : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(dockIcon.color == color ? .primary : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DockIconOptionButtonStyle())
                        .help("Use \(color.title) Dock icon")
                        .accessibilityLabel("\(color.title) Dock icon")
                        .accessibilityAddTraits(dockIcon.color == color ? [.isSelected] : [])
                        .accessibilityIdentifier("dockIcon\(color.rawValue.capitalized)")
                    }
                }
                Text("The selected color is used when Show in Dock is enabled. The menu bar icon stays monochrome.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .modifier(SettingsCard())
        }
    }

    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Keyboard shortcuts")
            VStack(spacing: 0) {
                shortcutRow(
                    title: "Show Clipboard History",
                    description: "Global · Available in any app",
                    icon: Image(nsImage: PasketMenuIcon.image),
                    shortcut: shortcuts.shortcut,
                    action: .showHistory
                )
                Divider().opacity(0.35).padding(.leading, 40)
                shortcutRow(
                    title: "Open Settings",
                    description: "History panel only",
                    icon: Image(systemName: "gearshape"),
                    shortcut: shortcuts.settingsShortcut,
                    action: .openSettings
                )
                Divider().opacity(0.35).padding(.leading, 40)
                shortcutRow(
                    title: "Delete Selected Item",
                    description: "History panel only · Optional",
                    icon: Image(systemName: "trash"),
                    shortcut: shortcuts.deletionShortcut,
                    action: .deleteSelectedItem
                )
                Divider().opacity(0.35).padding(.leading, 40)
                shortcutRow(
                    title: "Paste Next",
                    description: "Paste one queued item when pressed · Optional",
                    icon: Image(systemName: "text.insert"),
                    shortcut: shortcuts.pasteNextShortcut,
                    action: .pasteNext
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
        title: String, description: String, icon: Image,
        shortcut: GlobalShortcut?, action: GlobalShortcutManager.RecordingAction
    ) -> some View {
        HStack(spacing: 8) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            SettingsLabel(title: title, detail: description)
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
            if action == .openSettings {
                Button {
                    shortcuts.beginRecording(.openSettings)
                    shortcuts.stageShortcut(.defaultSettings)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 14, height: 16)
                }
                .buttonStyle(PasketButtonStyle())
                .disabled(shortcut == .defaultSettings)
                .help("Restore Default (⌘,)")
                .accessibilityLabel("Restore \(title) shortcut to default")
            } else {
                Color.clear
                    .frame(width: 32, height: 26)
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
            ShortcutKeycap(key: keys)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

}

struct PasketSetupView: View {
    @Bindable var setup: AppSetup
    @Bindable var shortcuts: GlobalShortcutManager
    var onRequestPermission: (SystemAccessController.Permission) -> Void
    var onFinish: () -> Void
    var onRelaunch: () -> Void
    var onResize: (CGFloat) -> Void = { _ in }
    @State private var showsPermissionHelp = false
    @State private var neverAskAgain = false
    @State private var hasRecordedShortcut = false
    @State private var guideContentHeight: CGFloat = 460

    private var showsShortcutGuide: Bool {
        !setup.neverAskForShortcut && (shortcuts.shortcut == nil || hasRecordedShortcut)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: PasketMenuIcon.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Pasket")
                        .font(.system(size: 16, weight: .medium))
                    Text("A little setup, then you're ready.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Setup")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.primary.opacity(0.045), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay { PasketWindowDragRegion() }
            .help("Drag the header to move setup")
            .accessibilityIdentifier("setupWindowDragArea")
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if setup.needsClipboardAccess {
                        permissionContent(for: .clipboard)
                    }
                    if setup.needsPasteAccess {
                        permissionContent(for: .accessibility)
                    }
                    if showsShortcutGuide {
                        shortcutGuidance
                    } else if setup.canContinue {
                        Label("You're ready to use Pasket.", systemImage: "checkmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    guideContentHeight = height
                }
            }
            .frame(height: min(guideContentHeight, 460))
            .scrollDisabled(guideContentHeight <= 460)
            guideFooter
        }
        .frame(width: 560)
        .modifier(PasketSurface())
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            onResize(height)
        }
        .sheet(isPresented: Binding(
            get: { shortcuts.isRecording },
            set: { if !$0 { shortcuts.cancelRecording() } }
        )) {
            ShortcutRecordingView(shortcuts: shortcuts, onSave: {
                hasRecordedShortcut = true
                refresh()
            })
            .presentationBackground(.clear)
        }
        .onAppear { neverAskAgain = setup.neverAskForShortcut }
        .onChange(of: setup.canContinue) {
            if !setup.canContinue, shortcuts.isRecording { shortcuts.cancelRecording() }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                refresh()
            }
        }
    }

    private func permissionContent(for permission: SystemAccessController.Permission) -> some View {
        let isClipboardStep = permission == .clipboard
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isClipboardStep ? "Keep what you copy" : "Paste back into your apps")
                    .font(.system(size: 18, weight: .medium))
                Text(isClipboardStep
                     ? "Allow clipboard access so Pasket can collect your copied items."
                     : "Allow Accessibility access to paste a history item straight into the app you're using.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                permissionInstruction(
                    number: "1",
                    title: isClipboardStep ? "Open clipboard settings" : "Open Accessibility settings",
                    detail: isClipboardStep ? "Privacy & Security → Paste from Other Apps"
                        : "Privacy & Security → Accessibility",
                    actionTitle: "Open System Settings…",
                    action: { onRequestPermission(permission) }
                )
                Divider().opacity(0.35).padding(.leading, 44)
                permissionInstruction(
                    number: "2",
                    title: isClipboardStep ? "Choose Always Allow for Pasket" : "Enable Pasket",
                    detail: isClipboardStep ? "Once access is allowed, setup continues automatically."
                        : "Turn on the switch next to Pasket."
                )
                if !isClipboardStep {
                    Divider().opacity(0.35).padding(.leading, 44)
                    permissionInstruction(
                        number: "3",
                        title: "Reopen Pasket to apply access",
                        detail: "After enabling access, reopen Pasket to continue. Your setup progress is kept.",
                        actionTitle: "Quit & Reopen Pasket",
                        action: onRelaunch
                    )
                }
            }
            .modifier(SettingsCard())
            if isClipboardStep {
                HStack(spacing: 6) {
                    Image(systemName: "circle.dotted")
                    Text("Waiting for access")
                    Spacer()
                    Button("Check Again") { refresh() }
                        .buttonStyle(PasketButtonStyle())
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                DisclosureGroup("Pasket not listed?", isExpanded: $showsPermissionHelp) {
                    Text("Copy some text, then click Open System Settings again. This lets macOS add Pasket to the list.")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disclosureGroupStyle(.automatic)
            }
        }
    }

    private var shortcutGuidance: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose your shortcut")
                    .font(.system(size: 18, weight: .medium))
                Text("Open clipboard history from any app with a combination that feels familiar. You can also use the menu bar without a shortcut.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Show Clipboard History")
                        .font(.system(size: 12, weight: .medium))
                    if let shortcut = shortcuts.shortcut {
                        ShortcutKeycaps(shortcut: shortcut)
                    } else {
                        Text("No shortcut set")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(shortcuts.shortcut == nil ? "Set Shortcut…" : "Change Shortcut…") {
                    shortcuts.beginRecording(.showHistory)
                }
                .buttonStyle(PasketButtonStyle(isProminent: true))
                .disabled(!setup.canContinue)
                .fixedSize()
            }
            .padding(12)
            .modifier(SettingsCard())
            if !setup.canContinue {
                Text("Allow access above, then choose your shortcut.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Toggle("Never ask again", isOn: $neverAskAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help("Stop shortcut reminders at launch. Missing permissions will still be shown.")
                .accessibilityIdentifier("neverAskForInvocationShortcut")
            Text("You can always add or change a shortcut in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func permissionInstruction(
        number: String, title: String, detail: String,
        actionTitle: String? = nil, action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.primary.opacity(0.045), in: PasketShape.compact)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PasketButtonStyle(isProminent: true))
                    .fixedSize()
            }
        }
        .padding(12)
    }

    private var guideFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack {
                Button("Quit Pasket") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(PasketButtonStyle())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    if setup.finishShortcutSetup(hasShortcut: shortcuts.shortcut != nil, neverAskAgain: neverAskAgain) {
                        onFinish()
                    }
                }
                .buttonStyle(PasketButtonStyle(isProminent: true))
                .disabled(!setup.canContinue || shortcuts.isRecording)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func refresh() {
        setup.refresh(hasShortcut: shortcuts.shortcut != nil)
    }

}

struct ShortcutRecordingView: View {
    @Bindable var shortcuts: GlobalShortcutManager
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    var onSkip: () -> Void = {}
    var isPasteQueueSetup = false

    private var hasSavedShortcut: Bool {
        switch shortcuts.recordingAction {
        case .showHistory: shortcuts.shortcut != nil
        case .openSettings: shortcuts.settingsShortcut != nil
        case .deleteSelectedItem: shortcuts.deletionShortcut != nil
        case .pasteNext: shortcuts.pasteNextShortcut != nil
        }
    }

    var body: some View {
        content
            .frame(width: 440)
            .modifier(PasketSurface())
            .interactiveDismissDisabled()
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPasteQueueSetup ? "Set Paste Next Shortcut" : "Record a shortcut")
                        .font(.system(size: 16, weight: .medium))
                    Text(shortcuts.recordingAction.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 12) {
                if isPasteQueueSetup {
                    Text("Starting the queue pastes the first item. Set a shortcut to paste each remaining item, or skip for now and use Paste Next in the menu or history panel.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if let pending = shortcuts.pendingShortcut {
                        ShortcutKeycaps(shortcut: pending)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: shortcuts.isClearingShortcut ? "minus.circle" : "record.circle")
                                .foregroundStyle(.secondary)
                            Text(shortcuts.isClearingShortcut ? "No shortcut" : "Press a key combination")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(.primary.opacity(0.035), in: PasketShape.card)
                .overlay {
                    PasketShape.card
                        .strokeBorder(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use Command, Control, or Option with another key.")
                    Text("Record again to change it. Nothing changes until you save.")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let error = shortcuts.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            ShortcutEventMonitor { event in
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers.isEmpty, [UInt16(kVK_Tab), UInt16(kVK_Return), UInt16(kVK_Space)].contains(event.keyCode) {
                    return false
                }
                if event.keyCode == UInt16(kVK_Escape) {
                    shortcuts.cancelRecording()
                    onCancel()
                    return true
                }
                shortcuts.record(event)
                return true
            }
                .frame(height: 1)
                .accessibilityHidden(true)
            Divider().opacity(0.5)
            HStack {
                if isPasteQueueSetup {
                    Button("Skip for Now", action: onSkip)
                } else if hasSavedShortcut {
                    Button("Clear Shortcut", role: .destructive) {
                        shortcuts.stageShortcut(nil)
                    }
                    .accessibilityLabel("Clear \(shortcuts.recordingAction.title) shortcut")
                }
                Spacer()
                Button {
                    shortcuts.cancelRecording()
                    onCancel()
                } label: {
                    HStack(spacing: 8) {
                        Text("Cancel")
                        Text("esc").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                Button(isPasteQueueSetup ? "Save & Start Queue" : "Save Shortcut") {
                    if shortcuts.saveRecording() { onSave() }
                }
                .disabled(!shortcuts.canSaveRecording)
                .buttonStyle(PasketButtonStyle(isProminent: true))
                .accessibilityIdentifier("saveRecordedShortcut")
            }
            .buttonStyle(PasketButtonStyle())
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

private struct DockIconOptionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isInteracting = isEnabled && (isHovered || configuration.isPressed)
        configuration.label
            .background(alignment: .top) {
                PasketShape.control
                    .fill(.primary.opacity(isEnabled && configuration.isPressed ? 0.12 : isInteracting ? 0.06 : 0))
                    .frame(height: 72)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isInteracting)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct AccentColorSwatchButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isInteracting = isEnabled && (isHovered || configuration.isPressed)
        configuration.label
            .background {
                Circle().fill(.primary.opacity(isInteracting ? 0.08 : 0))
            }
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(isInteracting && !isSelected ? 0.3 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(reduceMotion ? 1 : isEnabled && configuration.isPressed ? 0.94 : isInteracting ? 1.08 : 1)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isInteracting)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct HistoryRetentionSettingsView: View {
    @Bindable var store: ClipboardStore
    @Binding var focusedField: HistoryLimitField?
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
                Divider().opacity(0.35).padding(.horizontal, 12)
                SettingsToggleRow(
                    title: "Auto Recycle Unavailable Items",
                    detail: "Remove unavailable file entries when history closes, at most once every 5 minutes. Original files are kept.",
                    isOn: $draft.autoRecycleUnavailableFiles,
                    accessibilityIdentifier: "autoRecycleUnavailableFiles"
                )
                .padding(12)
                Divider().opacity(0.35)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apply to save these settings. History limits are checked at startup, after writes, every hour, and after waking from sleep. Original files stay untouched.")
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
                            focusedField = nil
                            draft = HistoryRetentionDraft(.default)
                        }
                            .buttonStyle(PasketButtonStyle())
                        Spacer()
                        if store.isApplyingRetention { ProgressView().controlSize(.small) }
                        Button("Apply") { apply() }
                            .buttonStyle(PasketButtonStyle(isProminent: true))
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
        let isFocused = focusedField == field
        return HStack(spacing: 12) {
            SettingsLabel(title: title, detail: detail)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                SettingsTextField(text: value.number, isFocused: Binding(
                    get: { focusedField == field },
                    set: { focused in
                        if focused { focusedField = field }
                        else if focusedField == field { focusedField = nil }
                    }
                ), label: title)
                Button { focusedField = field } label: {
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
            .padding(.horizontal, 8)
            .frame(width: 108, height: 26)
            .background {
                Button { focusedField = field } label: {
                    PasketShape.control.fill(.primary.opacity(0.035))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityHidden(true)
            }
            .overlay {
                PasketShape.control
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
                    if focusedField == field { focusedField = nil }
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
        .padding(18)
        .frame(width: 420)
        .modifier(PasketSurface())
        .interactiveDismissDisabled()
    }

    private func apply(confirmed: ClipboardRetentionPlan? = nil) {
        guard let settings = draft.settings else { return }
        focusedField = nil
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
    var autoRecycleUnavailableFiles: Bool

    init(_ settings: ClipboardRetention) {
        days = HistoryLimitDraft(settings.maximumAgeDays)
        items = HistoryLimitDraft(settings.maximumItems)
        text = HistoryLimitDraft(settings.maximumTextBytes, unit: ClipboardRetention.mebibyte)
        images = HistoryLimitDraft(settings.maximumImageBytes, unit: ClipboardRetention.mebibyte)
        autoRecycleUnavailableFiles = settings.autoRecycleUnavailableFiles
    }

    var settings: ClipboardRetention? {
        guard [days, items, text, images].allSatisfy(\.isValid) else { return nil }
        let settings = ClipboardRetention(maximumItems: items.value(),
                                          maximumTextBytes: text.value(unit: ClipboardRetention.mebibyte),
                                          maximumImageBytes: images.value(unit: ClipboardRetention.mebibyte),
                                          maximumAgeDays: days.value(),
                                          autoRecycleUnavailableFiles: autoRecycleUnavailableFiles)
        return settings.isValid ? settings : nil
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let accessibilityIdentifier: String

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityHint(detail)
        }
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 12)
                control()
            }
            .frame(minHeight: 24)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            .background(.primary.opacity(0.035), in: PasketShape.card)
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
                ShortcutKeycap(key: key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.displayName)
    }
}

private struct ShortcutKeycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .frame(minWidth: 12)
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(.primary.opacity(0.045), in: PasketShape.compact)
            .overlay {
                PasketShape.compact.strokeBorder(.primary.opacity(0.08))
                    .allowsHitTesting(false)
            }
    }
}

struct PasketWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        private var mouseDownEvent: NSEvent?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownEvent, let window else { return }
            let distance = hypot(event.locationInWindow.x - start.locationInWindow.x,
                                 event.locationInWindow.y - start.locationInWindow.y)
            guard distance >= 8 else { return }
            // AppKit needs the original mouse-down event and may consume mouse-up.
            mouseDownEvent = nil
            window.performDrag(with: start)
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownEvent = nil
        }
    }
}

struct ShortcutEventMonitor: NSViewRepresentable {
    var onFlagsChanged: ((NSEvent) -> Void)? = nil
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKeyDown = onKeyDown
        view.onFlagsChanged = onFlagsChanged
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onFlagsChanged = onFlagsChanged
    }

    static func dismantleNSView(_ nsView: CaptureView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class CaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        var onFlagsChanged: ((NSEvent) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      window.attachedSheet == nil, event.window === window else { return event }
                if event.type == .flagsChanged {
                    self.onFlagsChanged?(event)
                    return event
                }
                return self.onKeyDown?(event) == true ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

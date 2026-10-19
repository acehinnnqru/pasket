import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ClipboardStore
    @Bindable var shortcuts: GlobalShortcutManager
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void
    var onRestoreFileAccess: (ClipboardItem) -> Void = { _ in }

    @FocusState private var searchFocused: Bool
    @State private var isFilterMenuPresented = false
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            if store.clipboardAccessDenied {
                HStack {
                    Label("Clipboard access is denied. Allow Pasket in System Settings, then copy again.", systemImage: "hand.raised")
                        .font(.caption)
                    Spacer()
                    Button("System Settings…") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.orange.opacity(0.1))
            }
            if let error = store.storageError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                    Spacer()
                    Button("Retry") { Task { await store.retryStorage() } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
            }
            HStack(spacing: 0) {
                historyList.frame(width: 292)
                Divider().opacity(0.45)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().opacity(0.5)
            footer
        }
        .buttonStyle(PasketButtonStyle())
        .background {
            ShortcutEventMonitor { event in
                guard !isFilterMenuPresented, !isConfirmingClear, !shortcuts.isRecording,
                      shortcuts.deletionShortcut?.matches(event) == true else { return false }
                if !event.isARepeat, !store.isLoading, !store.isStorageBlocked,
                   let item = store.selectedItem {
                    store.delete(item.id)
                }
                return true
            }
        }
        .modifier(PasketSurface())
        .frame(minWidth: 760, minHeight: 480)
        .overlay(alignment: .topTrailing) {
            if isFilterMenuPresented {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissFilterMenu)
                        .accessibilityHidden(true)
                    ClipboardFilterMenu(selection: store.filter, onSelect: { filter in
                        store.filter = filter
                        dismissFilterMenu()
                    }, onDismiss: dismissFilterMenu)
                    .padding(.top, 52)
                    .padding(.trailing, 16)
                }
            }
        }
        .onAppear { searchFocused = true }
        .task(id: store.selectedItem?.id) { await store.loadPreview(for: store.selectedItem) }
        .onChange(of: store.presentationID) {
            isFilterMenuPresented = false
            searchFocused = true
        }
        .onChange(of: isConfirmingClear) {
            if !isConfirmingClear { searchFocused = true }
        }
        .onExitCommand {
            if isFilterMenuPresented { dismissFilterMenu() } else { onDismiss() }
        }
        .alert("Clear Clipboard History?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("Delete all \(store.items.count.formatted()) saved items and their image copies? This cannot be undone. Your original files and current system clipboard will be kept.")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("Search your clipboard…", text: $store.query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("clipboardSearch")
                .font(.system(size: 16))
                .focused($searchFocused)
                .onSubmit(copySelection)
                .onKeyPress(.downArrow) {
                    store.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    store.moveSelection(by: -1)
                    return .handled
                }
            Button {
                searchFocused = false
                isFilterMenuPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.filter.symbol)
                        .foregroundStyle(.secondary)
                    Text(store.filter.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFilterMenuPresented ? 180 : 0))
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(PasketButtonStyle(isActive: isFilterMenuPresented))
            .fixedSize()
            .accessibilityLabel("Filter clipboard history")
            .accessibilityValue(store.filter.title)
            .accessibilityHint("Show content type options")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    Text("History")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.top, 4)
                        .padding(.bottom, 5)
                    if store.isLoading {
                        ProgressView("Loading history…").frame(maxWidth: .infinity).padding()
                    } else if store.filteredItems.isEmpty {
                        if store.items.isEmpty {
                            ContentUnavailableView("Your basket is empty", systemImage: "basket",
                                description: Text(store.isPaused ? "Resume collection to save new copies." : "Copy text, an image, or a file to get started."))
                                .frame(maxWidth: .infinity)
                        } else {
                            ContentUnavailableView.search(text: store.query).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(store.filteredItems) { item in
                        Button {
                            store.selectedID = item.id
                            searchFocused = true
                        } label: {
                            HistoryRow(item: item, isSelected: store.selectedID == item.id,
                                       thumbnail: store.thumbnails[item.id], isUnavailable: store.unavailableItems.contains(item.id))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            store.selectedID = item.id
                            searchFocused = true
                            copySelection()
                        })
                        .id(item.id)
                        .accessibilityLabel("\(item.title), \(item.kind.title), from \(item.source.name)")
                        .task(id: item.id) { await store.loadThumbnail(for: item) }
                        .contextMenu {
                            Button("Delete", role: .destructive) { store.delete(item.id) }
                                .disabled(store.isStorageBlocked)
                        }
                    }
                }
                .padding(8)
            }
            .focusable(false)
            .onChange(of: store.selectedID) {
                if let id = store.selectedID { proxy.scrollTo(id) }
            }
        }
        .onChange(of: store.query) { store.reconcileSelection() }
        .onChange(of: store.filter) { store.reconcileSelection() }
    }

    @ViewBuilder
    private var preview: some View {
        if let item = store.selectedItem {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.kind.title.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Group {
                        switch item.kind {
                        case .image:
                            imagePreview(for: item)
                        case .file:
                            VStack(alignment: .leading, spacing: 12) {
                                if item.hasImagePreview {
                                    imagePreview(for: item)
                                } else {
                                    Image(systemName: "doc.richtext")
                                        .font(.system(size: 32, weight: .light))
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.title).font(.system(size: 15, weight: .medium))
                                Text(item.content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text("File references only. Original files are kept in their current location.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if store.unavailableItems.contains(item.id) {
                                    Label("A file is missing or access has expired.", systemImage: "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.orange)
                                } else if item.files.contains(where: { $0.isSecurityScoped != true }) {
                                    Text("Some files may need access restored after relaunch. Use Restore File Access… to keep access.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Button("Restore File Access…") { onRestoreFileAccess(item) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        default:
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.previewText)
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if item.hasTruncatedPreview {
                                    Text("Preview shows the first 500 characters. Copy includes all \(item.content.count.formatted()) characters.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                VStack(spacing: 2) {
                    informationRow("Source", value: item.source.name, shaded: true)
                    informationRow("Type", value: item.kind.title)
                    informationRow("Copied", value: item.copiedAt.formatted(date: .abbreviated, time: .shortened), shaded: true)
                    if [.text, .link, .email].contains(item.kind) {
                        informationRow("Characters", value: item.content.count.formatted())
                    } else if item.kind == .file {
                        informationRow("Files", value: item.files.count.formatted())
                        informationRow("Original size", value: item.files.allSatisfy { $0.byteCount != nil }
                            ? ByteCountFormatter.string(fromByteCount: Int64(item.files.compactMap(\.byteCount).reduce(0, +)), countStyle: .file)
                            : "Unknown")
                    }
                }
                .font(.system(size: 12))
            }
            .padding(20)
        } else {
            ContentUnavailableView("No matching items", systemImage: "magnifyingglass", description: Text("Try another search or content type."))
        }
    }

    private func imagePreview(for item: ClipboardItem) -> some View {
        VStack(spacing: 10) {
            if store.previewID == item.id, let image = store.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            } else if store.missingPreviews.contains(item.id) {
                Label(store.unavailableItems.contains(item.id) ? "Image unavailable" : "Preview unavailable",
                      systemImage: "photo")
            } else {
                ProgressView("Loading preview…")
            }
            if let image = item.image {
                Text("\(image.width) × \(image.height) · \(ByteCountFormatter.string(fromByteCount: Int64(image.byteCount), countStyle: .file))")
                    .font(.system(size: 12))
            }
        }
        .padding(12)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func informationRow(_ title: String, value: String, shaded: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(shaded ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.copyError ?? store.notice {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("clipboardNotice")
            }
            HStack(spacing: 6) {
            Label(store.clipboardAccessDenied ? "Access denied" : store.isPaused ? "Paused" : "\(store.items.count) items",
                  systemImage: store.clipboardAccessDenied ? "hand.raised" : store.isPaused ? "pause.circle" : "basket")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help("Up to 1,000 items. Text is limited to 2,000 characters; image storage to 500 MB.")
            Spacer()
            Button(store.isPaused ? "Resume" : "Pause", systemImage: store.isPaused ? "play" : "pause") {
                store.setPaused(!store.isPaused)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(PasketButtonStyle(isActive: store.isPaused))
            .focusable(false)
            .disabled(store.isLoading || store.isStorageBlocked)
            .help(store.isPaused ? "Resume collection" : "Pause collection")
            Button(role: .destructive) {
                if let item = store.selectedItem { store.delete(item.id) }
                searchFocused = true
            } label: {
                Label("Delete Selected", systemImage: "trash")
            }
            .buttonStyle(PasketButtonStyle())
            .font(.system(size: 12))
            .focusable(false)
            .fixedSize()
            .disabled(store.selectedItem == nil || store.isLoading || store.isStorageBlocked)
            .help(shortcuts.deletionShortcut.map { "Delete the selected history entry (\($0.displayName))" }
                  ?? "Delete the selected history entry")
            .accessibilityIdentifier("deleteSelectedClipboardItem")
            Button("Clear All…", role: .destructive) { isConfirmingClear = true }
                .buttonStyle(PasketButtonStyle())
                .font(.system(size: 12))
                .focusable(false)
                .fixedSize()
                .disabled(store.items.isEmpty || store.isLoading || store.isStorageBlocked)
                .help("Clear all clipboard history after confirmation")
                .accessibilityIdentifier("clearClipboardHistory")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(PasketButtonStyle())
            .focusable(false)
            .help("Settings")
            .accessibilityLabel("Open settings")
            Button(action: copySelection) {
                HStack(spacing: 8) {
                    Text("Copy")
                    Image(systemName: "return").foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(PasketButtonStyle(isProminent: true))
            .focusable(false)
            .disabled(!store.canCopySelection)
            .help("Copy the complete item and return to your previous app")
            .accessibilityIdentifier("copyClipboardItem")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func copySelection() {
        let presentation = store.presentationID
        Task {
            if await store.copySelection(), store.presentationID == presentation { onDismiss() }
        }
    }

    private func dismissFilterMenu() {
        isFilterMenuPresented = false
        searchFocused = true
    }
}

private struct ClipboardFilterMenu: View {
    let selection: ClipboardFilter
    var onSelect: (ClipboardFilter) -> Void
    var onDismiss: () -> Void

    @State private var highlightedFilter: ClipboardFilter?
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CONTENT TYPE")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ForEach(ClipboardFilter.allCases) { filter in
                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: filter.symbol)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                        Text(filter.title)
                            .font(.system(size: 13, weight: selection == filter ? .medium : .regular))
                        Spacer(minLength: 12)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(selection == filter ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.primary.opacity(highlightedFilter == filter ? 0.09 : selection == filter ? 0.05 : 0))
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { hovering in
                    if hovering {
                        highlightedFilter = filter
                    } else if highlightedFilter == filter {
                        highlightedFilter = nil
                    }
                }
                .accessibilityAddTraits(selection == filter ? .isSelected : [])
            }
        }
        .padding(8)
        .frame(width: 204)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(colorScheme == .dark ? 0.025 : 0.16))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.65))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 22, x: 0, y: 10)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            highlightedFilter = selection
            isFocused = true
        }
        .onKeyPress(.downArrow) {
            moveHighlight(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveHighlight(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            onSelect(highlightedFilter ?? selection)
            return .handled
        }
        .onExitCommand(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Content type options")
    }

    private func moveHighlight(by offset: Int) {
        let filters = ClipboardFilter.allCases
        let current = filters.firstIndex(of: highlightedFilter ?? selection) ?? 0
        highlightedFilter = filters[(current + offset + filters.count) % filters.count]
    }
}

private struct HistoryRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    var thumbnail: NSImage?
    var isUnavailable = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(systemName: item.hasImagePreview ? "photo" : isUnavailable ? "exclamationmark.triangle" : item.kind.symbol)
                }
            }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 13)).lineLimit(1)
                Text("\(item.source.name) · \(item.copiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(isHovered ? 0.18 : 0.12)
                      : Color.primary.opacity(isHovered ? 0.055 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.2 : 0))
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

struct PasketButtonStyle: ButtonStyle {
    var isProminent = false
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isDestructive = configuration.role == .destructive
        let isInteracting = isEnabled && (isHovered || configuration.isPressed)
        let tint: Color = isDestructive ? .red : isProminent || isActive ? .accentColor : .primary

        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(isDestructive && !isInteracting ? Color.secondary : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(isEnabled && configuration.isPressed ? 0.2
                                       : isInteracting ? 0.12
                                       : isProminent || isActive ? 0.08 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(isInteracting ? 0.2 : isProminent || isActive ? 0.12 : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isInteracting)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PasketSurface: ViewModifier {
    var cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                VisualEffectBackground()
                    .overlay(Color.white.opacity(colorScheme == .dark ? 0.025 : 0.12))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.6), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
    ContentView(store: ClipboardStore(), shortcuts: GlobalShortcutManager(), onDismiss: {}, onOpenSettings: {})
        .frame(width: 800, height: 520)
}

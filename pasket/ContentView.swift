import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ClipboardStore
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void
    var onRestoreFileAccess: (ClipboardItem) -> Void = { _ in }

    @FocusState private var searchFocused: Bool
    @State private var isFilterMenuPresented = false
    @State private var isConfirmingClear = false
    @Environment(\.colorScheme) private var colorScheme

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
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(.orange.opacity(0.1))
            }
            if let error = store.storageError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                    Spacer()
                    Button("Retry") { Task { await store.retryStorage() } }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.1))
            }
            HStack(spacing: 0) {
                historyList.frame(width: 350)
                Divider().opacity(0.45)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().opacity(0.5)
            footer
        }
        .background {
            VisualEffectBackground()
                .overlay(Color.white.opacity(colorScheme == .dark ? 0.025 : 0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.6), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(minWidth: 820, minHeight: 540)
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
                    .padding(.top, 76)
                    .padding(.trailing, 26)
                }
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: store.presentationID) {
            isFilterMenuPresented = false
            searchFocused = true
        }
        .onExitCommand {
            if isFilterMenuPresented { dismissFilterMenu() } else { onDismiss() }
        }
        .alert("Clear Clipboard History?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("All saved history and image copies will be deleted. Your original files and current system clipboard will be kept.")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("Search your clipboard…", text: $store.query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("clipboardSearch")
                .font(.system(size: 23))
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
                HStack(spacing: 9) {
                    Image(systemName: store.filter.symbol)
                        .foregroundStyle(.secondary)
                    Text(store.filter.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFilterMenuPresented ? 180 : 0))
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(isFilterMenuPresented ? 0.45 : 0.2)))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Filter clipboard history")
            .accessibilityValue(store.filter.title)
            .accessibilityHint("Show content type options")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 23)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    Text("History")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
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
                        } label: {
                            HistoryRow(item: item, isSelected: store.selectedID == item.id,
                                       thumbnail: store.thumbnails[item.id], isUnavailable: store.unavailableItems.contains(item.id))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            store.selectedID = item.id
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
                .padding(12)
            }
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
            VStack(alignment: .leading, spacing: 22) {
                Text(item.kind.title.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Group {
                        switch item.kind {
                        case .image:
                            VStack(spacing: 14) {
                                if let thumbnail = store.thumbnails[item.id] {
                                    Image(nsImage: thumbnail)
                                        .resizable().scaledToFit().frame(maxHeight: 260)
                                } else if store.missingPreviews.contains(item.id) {
                                    Label(store.unavailableItems.contains(item.id) ? "Saved image unavailable" : "Preview unavailable",
                                          systemImage: "exclamationmark.triangle")
                                } else {
                                    ProgressView("Loading preview…")
                                }
                                if let image = item.image {
                                    Text("\(image.width) × \(image.height) · \(ByteCountFormatter.string(fromByteCount: Int64(image.byteCount), countStyle: .file))")
                                        .font(.system(size: 12))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 190)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
                        case .file:
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: "doc.richtext")
                                    .font(.system(size: 42, weight: .ultraLight))
                                    .foregroundStyle(.secondary)
                                Text(item.title).font(.title3)
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
                                    .font(.system(size: 17))
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
            .padding(28)
            .task(id: item.id) { await store.loadThumbnail(for: item) }
        } else {
            ContentUnavailableView("No matching items", systemImage: "magnifyingglass", description: Text("Try another search or content type."))
        }
    }

    private func informationRow(_ title: String, value: String, shaded: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(shaded ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.copyError ?? store.notice {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("clipboardNotice")
            }
            HStack(spacing: 12) {
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
            .disabled(store.isLoading || store.isStorageBlocked)
            .help(store.isPaused ? "Resume collection" : "Pause collection")
            Menu {
                Button("Delete Selected Item", role: .destructive) {
                    if let id = store.selectedID { store.delete(id) }
                }.disabled(store.selectedItem == nil || store.isStorageBlocked)
                Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                    .disabled(store.items.isEmpty || store.isStorageBlocked)
            } label: {
                Image(systemName: "trash")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Manage history")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Open settings")
            Button(action: copySelection) {
                HStack(spacing: 14) {
                    Text("Copy")
                    Image(systemName: "return").foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .disabled(!store.canCopySelection)
            .help("Copy the complete item and return to your previous app")
            .accessibilityIdentifier("copyClipboardItem")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
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
        VStack(alignment: .leading, spacing: 4) {
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
                    HStack(spacing: 11) {
                        Image(systemName: filter.symbol)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                        Text(filter.title)
                            .font(.system(size: 13, weight: selection == filter ? .medium : .regular))
                        Spacer(minLength: 12)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(selection == filter ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 13))
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
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
        .frame(width: 224)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(colorScheme == .dark ? 0.025 : 0.16))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(systemName: isUnavailable ? "exclamationmark.triangle" : item.kind.symbol)
                }
            }
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14)).lineLimit(1)
                Text("\(item.source.name) · \(item.copiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.3))
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
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
    ContentView(store: ClipboardStore(), onDismiss: {}, onOpenSettings: {})
        .frame(width: 920, height: 590)
}

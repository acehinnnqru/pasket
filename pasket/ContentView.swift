import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ClipboardStore
    @Bindable var shortcuts: GlobalShortcutManager
    @Bindable var pasteController: ClipboardPasteController
    var onDismiss: () -> Void
    var onPasteCopiedItem: () -> Void
    var onOpenSettings: () -> Void
    var onRelaunch: () -> Void = {}

    private struct PreviewIdentity: Equatable {
        let id: UUID
        let copiedAt: Date
    }

    private var previewIdentity: PreviewIdentity? {
        store.selectedItem.map { PreviewIdentity(id: $0.id, copiedAt: $0.copiedAt) }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var isFilterMenuPresented = false
    @State private var filterControlFrame: CGRect = .zero
    @State private var isMoreMenuPresented = false
    @State private var moreControlFrame: CGRect = .zero
    @State private var isConfirmingClear = false
    @State private var showsSearchProgress = false

    private var isMenuPresented: Bool { isFilterMenuPresented || isMoreMenuPresented }
    private var isDialogPresented: Bool { isConfirmingClear || store.systemAccess.request != nil }

    private var canClearHistory: Bool {
        !store.isDebugMode && store.totalCount > 0 && !store.isLoading && !store.isStorageBlocked
            && !store.isDeletingUnavailableFiles
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            contentArea
            Divider().opacity(0.5)
            footer
        }
        .buttonStyle(PasketButtonStyle())
        .background {
            WindowKeyStateObserver { isKey in
                searchFocused = isKey && !isMenuPresented && !isDialogPresented
            }
        }
        .background {
            ShortcutEventMonitor { event in
                guard !isDialogPresented, !shortcuts.isRecording else { return false }
                if shortcuts.settingsShortcut?.matches(event) == true {
                    if !event.isARepeat {
                        dismissMenus()
                        searchFocused = false
                        onOpenSettings()
                    }
                    return true
                }
                guard !isMenuPresented, shortcuts.deletionShortcut?.matches(event) == true else { return false }
                if !event.isARepeat, !store.isLoading, !store.isStorageBlocked,
                   let item = store.selectedItem {
                    store.delete(item.id)
                }
                return true
            }
        }
        .modifier(PasketSurface())
        .frame(minWidth: 760, minHeight: 480)
        .coordinateSpace(name: "clipboardPanel")
        .overlay(alignment: .bottom) {
            PasketToastOverlay(center: store.toasts, onAction: handleToastAction)
                .padding(.bottom, 56)
        }
        .overlay(alignment: .topTrailing) {
            if isFilterMenuPresented {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissFilterMenu)
                        .accessibilityHidden(true)
                    ClipboardFilterMenu(selection: store.filter, width: filterControlFrame.width, onSelect: { filter in
                        store.filter = filter
                        dismissFilterMenu()
                    }, onDismiss: dismissFilterMenu)
                    .padding(.top, filterControlFrame.maxY + 4)
                    .padding(.trailing, 14)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isMoreMenuPresented {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomTrailing) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: dismissMenus)
                            .accessibilityHidden(true)
                        ClipboardMoreActionsMenu(canClearHistory: canClearHistory, onSelect: { action in
                            dismissMenus()
                            switch action {
                            case .settings:
                                searchFocused = false
                                onOpenSettings()
                            case .clearHistory:
                                searchFocused = false
                                isConfirmingClear = true
                            case .deleteUnavailableFiles:
                                Task { await store.deleteUnavailableFiles() }
                            }
                        }, onDismiss: dismissMenus)
                        .padding(.bottom, geometry.size.height - moreControlFrame.minY + 4)
                        .padding(.trailing, geometry.size.width - moreControlFrame.maxX)
                    }
                }
            }
        }
        .task(id: previewIdentity) {
            await store.loadSelection()
            await store.loadPreview(for: store.selectedItem)
        }
        .task(id: store.isSearching) {
            showsSearchProgress = false
            guard store.isSearching else { return }
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                showsSearchProgress = true
            } catch {}
        }
        .onChange(of: store.presentationID) {
            isFilterMenuPresented = false
            isMoreMenuPresented = false
        }
        .onChange(of: store.query) { store.reconcileSelection() }
        .onChange(of: store.filter) { store.reconcileSelection() }
        .onChange(of: isConfirmingClear) {
            if !isConfirmingClear { searchFocused = true }
        }
        .onChange(of: store.systemAccess.request?.id) {
            if store.systemAccess.request != nil { dismissMenus() }
            searchFocused = !isDialogPresented
        }
        .onExitCommand {
            if isMenuPresented { dismissMenus() } else { onDismiss() }
        }
        .alert("Clear Clipboard History?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("Delete all \(store.totalCount.formatted()) saved items and their image copies? This cannot be undone. Your original files and current system clipboard will be kept.")
        }
        .alert(store.systemAccess.request?.title ?? "System Access", isPresented: Binding(
            get: { store.systemAccess.request != nil },
            set: { if !$0 { store.systemAccess.dismiss() } }
        ), presenting: store.systemAccess.request) { request in
            Button("Cancel", role: .cancel) { store.systemAccess.dismiss() }
            Button("Open System Settings…") { openSystemSettings(for: request.permission) }
            if request.permission == .accessibility {
                Button("Quit & Reopen Pasket") {
                    store.systemAccess.dismiss()
                    onRelaunch()
                }
            }
        } message: { request in
            Text(request.message)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .opacity(showsSearchProgress ? 0 : 1)
                .overlay {
                    if showsSearchProgress {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Searching history")
                    }
                }
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
            if store.filter != .all {
                Button {
                    store.filter = .all
                    dismissFilterMenu()
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: 18)
                }
                .buttonStyle(PasketButtonStyle(hasBackground: true))
                .fixedSize()
                .focusable(false)
                .help("Reset the content type filter to All Types")
                .accessibilityLabel("Reset content type filter")
                .accessibilityIdentifier("resetClipboardFilter")
            }
            Button {
                isMoreMenuPresented = false
                searchFocused = false
                isFilterMenuPresented.toggle()
                if !isFilterMenuPresented { searchFocused = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.filter.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(store.filter.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFilterMenuPresented ? 180 : 0))
                        .frame(width: 10)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 5)
                .frame(width: 130)
                .frame(minHeight: 18)
            }
            .buttonStyle(PasketButtonStyle(isActive: isFilterMenuPresented))
            .fixedSize()
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named("clipboardPanel"))
            } action: { frame in
                filterControlFrame = frame
            }
            .accessibilityLabel("Filter clipboard history")
            .accessibilityValue(store.filter.title)
            .accessibilityHint("Show content type options")
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
    }

    private var contentArea: some View {
        Group {
            if store.isLoading {
                ProgressView("Loading history…")
            } else if store.filteredItems.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    historyList.frame(width: 292)
                    Divider().opacity(0.45)
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.isDebugMode ? store.displayedItems.isEmpty : store.totalCount == 0 {
            ContentUnavailableView("Your basket is empty", systemImage: "basket",
                description: Text(store.isPaused ? "Resume collection to save new copies." : "Copy text, an image, or a file to get started."))
        } else {
            ContentUnavailableView("No matching items", systemImage: "magnifyingglass",
                description: Text("Try another search or content type."))
        }
    }

    private var historyList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            historyList(at: context.date)
        }
    }

    private func historyList(at date: Date) -> some View {
        let sections = ClipboardHistorySection.grouping(store.filteredItems, at: date)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                Button {
                                    store.selectedID = item.id
                                    searchFocused = true
                                } label: {
                                    HistoryRow(item: item, isSelected: store.selectedID == item.id,
                                               thumbnail: store.thumbnails[item.id], isUnavailable: store.unavailableItems.contains(item.id))
                                }
                                .buttonStyle(HistoryRowButtonStyle())
                                .focusable(false)
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    store.selectedID = item.id
                                    searchFocused = true
                                    copySelection()
                                })
                                .id(item.id)
                                .accessibilityLabel("\(item.title), \(item.kind.title), from \(item.source.name)")
                                .task(id: item.copiedAt) { await store.loadThumbnail(for: item) }
                                .contextMenu {
                                    Button("Delete", role: .destructive) { store.delete(item.id) }
                                        .disabled(store.isDebugMode || store.isStorageBlocked)
                                }
                            }
                        } header: {
                            Text(section.period.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.top, section.id == sections.first?.id ? 4 : 18)
                                .padding(.bottom, 5)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    if store.hasMoreItems && !store.isSearching {
                        ProgressView("Loading more…")
                            .frame(maxWidth: .infinity)
                            .task(id: store.items.last?.id) { await store.loadMore() }
                    }
                }
                .padding(8)
            }
            .focusable(false)
            .onChange(of: store.selectedID) {
                if let id = store.selectedID { proxy.scrollTo(id) }
            }
        }
        // Reset scrolling even when reopening keeps the same selected item.
        .id(store.presentationID)
    }

    @ViewBuilder
    private var preview: some View {
        if let item = store.selectedItem {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    switch item.kind {
                    case .image:
                        imagePreview(for: item)
                    case .file:
                        if item.hasImagePreview {
                            imagePreview(for: item)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(item.files.enumerated()), id: \.offset) { _, file in
                                        Label(file.name, systemImage: "doc")
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(file.name)
                                    }
                                }
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    default:
                        ScrollView {
                            Text(item.content)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
                information(for: item)
            }
            .padding(20)
        }
    }

    private func imagePreview(for item: ClipboardItem) -> some View {
        GeometryReader { geometry in
            Group {
                if store.previewID == item.id, let image = store.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else if store.missingPreviews.contains(item.id) {
                    Label(store.unavailableItems.contains(item.id)
                          ? (item.kind == .file ? "File unavailable" : "Image unavailable") : "Preview unavailable",
                          systemImage: "photo")
                } else {
                    ProgressView("Loading preview…")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(12)
        .foregroundStyle(.secondary)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func information(for item: ClipboardItem) -> some View {
        let rows = informationValues(for: item)
        return ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    informationRow(row.title, value: row.value, shaded: index.isMultiple(of: 2))
                }
            }
        }
        .font(.system(size: 12))
        .frame(height: min(CGFloat(rows.count) * 30 - 2, 180))
        .id(item.id)
    }

    private func informationValues(for item: ClipboardItem) -> [(title: String, value: String)] {
        var rows = [(title: "Source", value: item.source.name),
                    (title: "Type", value: item.kind.title),
                    (title: "Copied", value: item.copiedAt.formatted(date: .abbreviated, time: .shortened))]
        if [.text, .link, .email].contains(item.kind) {
            rows.append(("Characters", item.content.count.formatted()))
        } else if item.kind == .file {
            rows.append((item.files.count == 1 ? "Name" : "Names", item.files.map(\.name).joined(separator: ", ")))
            rows.append((item.files.count == 1 ? "Path" : "Paths", item.files.map(\.path).joined(separator: "\n")))
            rows.append(("Files", item.files.count.formatted()))
            rows.append(("Original size", item.files.allSatisfy { $0.byteCount != nil }
                ? ByteCountFormatter.string(fromByteCount: Int64(item.files.compactMap(\.byteCount).reduce(0, +)), countStyle: .file)
                : "Unknown"))
            if store.unavailableItems.contains(item.id) {
                rows.append(("Status", "File unavailable. Copy the original file again or delete this entry."))
            }
        }
        if let image = item.image {
            rows.append(("Dimensions", "\(image.width) × \(image.height)"))
            rows.append(("Size", ByteCountFormatter.string(fromByteCount: Int64(image.byteCount), countStyle: .file)))
        }
        return rows
    }

    private func informationRow(_ title: String, value: String, shaded: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 12)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(shaded ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private var collectionControl: some View {
        let isCollecting = !store.isPaused && !store.isDebugMode && !store.isLoading
            && !store.isStorageBlocked && !store.clipboardAccessDenied

        return Button {
            store.setPaused(store.clipboardAccessDenied ? false : !store.isPaused)
            searchFocused = true
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isCollecting || reduceMotion)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
                let intensity = reduceMotion ? 1 : (1 - cos(phase * 2 * .pi)) / 2

                Circle()
                    .fill(isCollecting ? Color.accentColor : Color.secondary)
                    .opacity(isCollecting ? 0.4 + 0.6 * intensity : 0.6)
                    .frame(width: 7, height: 7)
                    .shadow(color: isCollecting ? Color.accentColor.opacity(0.08 + 0.47 * intensity) : .clear,
                            radius: 2 + 4 * intensity)
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
        }
        .buttonStyle(PasketButtonStyle())
        .focusable(false)
        .fixedSize()
        .disabled(store.isDebugMode || store.isLoading || store.isStorageBlocked)
        .help(store.clipboardAccessDenied ? "Allow Clipboard Access…" : store.isPaused ? "Resume" : "Pause")
        .accessibilityLabel("Clipboard collection")
        .accessibilityValue(store.clipboardAccessDenied ? "Clipboard access needed" : isCollecting ? "Collecting" : store.isPaused ? "Paused" : "Inactive")
        .accessibilityIdentifier("clipboardCollectionToggle")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            collectionControl
            Label("\(store.isDebugMode ? store.displayedItems.count : store.totalCount) items", systemImage: "basket")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Change history limits in Settings → History. Text entries are limited to 2,000 characters.")
            Spacer()
            #if DEBUG
            Toggle("Debug mode", isOn: Binding(get: { store.isDebugMode }, set: { enabled in
                isConfirmingClear = false
                dismissMenus()
                store.setDebugMode(enabled)
            }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
                .fixedSize()
                .disabled(store.isLoading || store.isCopying)
                .help("Show sample data for screenshots")
                .accessibilityIdentifier("debugModeToggle")
            #endif
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
            .disabled(store.isDebugMode || store.selectedItem == nil || store.isLoading || store.isStorageBlocked)
            .help(shortcuts.deletionShortcut.map { "Delete the selected history entry (\($0.displayName))" }
                  ?? "Delete the selected history entry")
            .accessibilityIdentifier("deleteSelectedClipboardItem")
            Button(action: copySelection) {
                HStack(spacing: 8) {
                    Text("Paste")
                    Image(systemName: "return").foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(PasketButtonStyle(isProminent: true))
            .focusable(false)
            .disabled(!store.canCopySelection)
            .help("Paste the complete item into your previous app")
            .accessibilityIdentifier("copyClipboardItem")
            Button {
                isFilterMenuPresented = false
                isMoreMenuPresented.toggle()
                searchFocused = !isMoreMenuPresented
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(PasketButtonStyle(isActive: isMoreMenuPresented))
            .focusable(false)
            .fixedSize()
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named("clipboardPanel"))
            } action: { frame in
                moreControlFrame = frame
            }
            .help("More actions")
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("clipboardMoreActions")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func handleToastAction(_ action: PasketToast.Action) {
        switch action {
        case .retryStorage:
            Task { await store.retryStorage() }
        case .reviewHistory:
            onOpenSettings()
        }
    }

    private func openSystemSettings(for permission: SystemAccessController.Permission) {
        store.systemAccess.dismiss()
        onDismiss()
        switch permission {
        case .accessibility:
            pasteController.openAccessibilitySettings()
        case .clipboard:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func copySelection() {
        let presentation = store.presentationID
        Task {
            if await store.copySelection(), store.presentationID == presentation { onPasteCopiedItem() }
        }
    }

    private func dismissFilterMenu() {
        isFilterMenuPresented = false
        searchFocused = true
    }

    private func dismissMenus() {
        isFilterMenuPresented = false
        isMoreMenuPresented = false
        searchFocused = true
    }
}

private struct WindowKeyStateObserver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: (Bool) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                center.addObserver(self, selector: #selector(windowKeyStateChanged), name: name, object: window)
            }
            windowKeyStateChanged()
        }

        @objc private func windowKeyStateChanged() {
            // Let AppKit finish changing the key window before SwiftUI requests the field editor.
            DispatchQueue.main.async { [weak self, weak window = window] in
                guard let self, let window, self.window === window else { return }
                self.onChange(window.isKeyWindow)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private struct ClipboardFilterMenu: View {
    let selection: ClipboardFilter
    let width: CGFloat
    var onSelect: (ClipboardFilter) -> Void
    var onDismiss: () -> Void

    @State private var highlightedFilter: ClipboardFilter?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClipboardFilter.allCases) { filter in
                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: filter.symbol)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(selection == filter ? Color.accentColor : .secondary)
                            .frame(width: 16)
                        Text(filter.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 10)
                            .opacity(selection == filter ? 1 : 0)
                    }
                    .foregroundStyle(selection == filter ? Color.accentColor : .primary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(selection == filter ? 0.08 : 0))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.primary.opacity(highlightedFilter == filter ? 0.04 : 0))
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
        .padding(6)
        .frame(width: width)
        .modifier(ClipboardMenuSurface())
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

private struct ClipboardMenuSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 12, x: 0, y: 5)
    }
}

private struct ClipboardMoreActionsMenu: View {
    enum Action: CaseIterable {
        case deleteUnavailableFiles, clearHistory, settings

        var title: String {
            switch self {
            case .deleteUnavailableFiles: "Delete Unavailable Files"
            case .clearHistory: "Delete All Entries…"
            case .settings: "Settings…"
            }
        }
        var symbol: String { self == .settings ? "gearshape" : "trash" }
        var help: String {
            switch self {
            case .deleteUnavailableFiles: "Remove history entries with unavailable files. Original files are kept."
            case .clearHistory: "Clear all clipboard history after confirmation"
            case .settings: "Open Settings"
            }
        }
        var accessibilityIdentifier: String {
            switch self {
            case .deleteUnavailableFiles: "deleteUnavailableClipboardFiles"
            case .clearHistory: "clearClipboardHistory"
            case .settings: "openPasketSettings"
            }
        }
    }

    let canClearHistory: Bool
    var onSelect: (Action) -> Void
    var onDismiss: () -> Void

    @State private var highlightedAction: Action? = .settings
    @FocusState private var isFocused: Bool

    private var enabledActions: [Action] { canClearHistory ? Action.allCases : [.settings] }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Action.allCases, id: \.self) { action in
                if action == .settings {
                    Divider().padding(.horizontal, 8).padding(.vertical, 4)
                }
                Button(role: action == .settings ? nil : .destructive) {
                    onSelect(action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 13, weight: .regular))
                            .frame(width: 16)
                        Text(action.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(action == .settings ? .primary : Color.red)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.primary.opacity(highlightedAction == action && enabledActions.contains(action) ? 0.04 : 0))
                    }
                    .opacity(enabledActions.contains(action) ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!enabledActions.contains(action))
                .onHover { hovering in
                    if hovering, enabledActions.contains(action) {
                        highlightedAction = action
                    } else if highlightedAction == action {
                        highlightedAction = nil
                    }
                }
                .help(action.help)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .padding(6)
        .frame(width: 208)
        .modifier(ClipboardMenuSurface())
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
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
            let action = highlightedAction ?? .settings
            if enabledActions.contains(action) { onSelect(action) }
            return .handled
        }
        .onExitCommand(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("More actions")
        .onChange(of: canClearHistory) {
            if let highlightedAction, !enabledActions.contains(highlightedAction) {
                self.highlightedAction = .settings
            }
        }
    }

    private func moveHighlight(by offset: Int) {
        let actions = enabledActions
        guard let highlightedAction, let current = actions.firstIndex(of: highlightedAction) else {
            self.highlightedAction = offset > 0 ? actions.first : actions.last
            return
        }
        self.highlightedAction = actions[(current + offset + actions.count) % actions.count]
    }
}

private struct HistoryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Selection is the row's feedback; pressing must not dim it before selection changes.
        configuration.label
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
                .fill(Color.primary.opacity(0.055))
                .opacity(isHovered && !isSelected ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .animation(nil, value: isSelected)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(isSelected ? 0.12 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.2 : 0))
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
    }
}

struct PasketButtonStyle: ButtonStyle {
    var isProminent = false
    var isActive = false
    var hasBackground = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isDestructive = configuration.role == .destructive
        let isInteracting = isEnabled && (isHovered || configuration.isPressed)
        let tint: Color = isDestructive ? .red : isProminent || isActive ? .accentColor : .primary
        let backgroundOpacity: Double = isEnabled && configuration.isPressed ? (hasBackground ? 0.12 : 0.2)
            : isInteracting ? (hasBackground ? 0.08 : 0.12)
            : isProminent || isActive ? 0.08 : hasBackground ? 0.05 : 0
        let borderOpacity: Double = isInteracting ? (hasBackground ? 0.12 : 0.2)
            : isProminent || isActive ? 0.12 : hasBackground ? 0.07 : 0

        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(isDestructive && !isInteracting ? Color.secondary : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(backgroundOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(borderOpacity))
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
    ContentView(store: ClipboardStore(), shortcuts: GlobalShortcutManager(),
                pasteController: ClipboardPasteController(), onDismiss: {},
                onPasteCopiedItem: {}, onOpenSettings: {})
        .frame(width: 800, height: 520)
}

import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ClipboardStore
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var isFilterMenuPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
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
    }

    private var searchBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("Search your clipboard…", text: $store.query)
                .textFieldStyle(.plain)
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
                    Text("Today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    if store.filteredItems.isEmpty {
                        ContentUnavailableView.search(text: store.query)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(store.filteredItems) { item in
                        Button {
                            store.selectedID = item.id
                        } label: {
                            HistoryRow(item: item, isSelected: store.selectedID == item.id)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            store.selectedID = item.id
                            copySelection()
                        })
                        .id(item.id)
                        .accessibilityLabel("\(item.title), \(item.kind.title), from \(item.source)")
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
                                Image(systemName: "photo")
                                    .font(.system(size: 52, weight: .ultraLight))
                                Text("Sample image")
                                    .font(.system(size: 14, weight: .medium))
                                Text("1440 × 900").font(.system(size: 12))
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
                                Text("Sample file reference")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        default:
                            Text(item.content)
                                .font(.system(size: 17, design: item.isCode ? .monospaced : .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.bottom, 8)
                }
                VStack(spacing: 2) {
                    informationRow("Source", value: item.source, shaded: true)
                    informationRow("Type", value: item.kind.title)
                    informationRow("Copied", value: item.copiedAt.formatted(date: .omitted, time: .shortened), shaded: true)
                    if item.kind == .text {
                        informationRow("Characters", value: item.content.count.formatted())
                    }
                }
                .font(.system(size: 12))
            }
            .padding(28)
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
        HStack(spacing: 12) {
            Text("Sample history")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help("Live clipboard collection and history storage will be connected next.")
            Spacer()
            if let message = store.copyError {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
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
            .disabled(store.selectedItem?.canCopy != true)
            .help(store.selectedItem?.canCopy == true ? "Copy and return to your previous app" : "This sample has no clipboard payload")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }

    private func copySelection() {
        if store.copySelection() { onDismiss() }
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCode ? "chevron.left.forwardslash.chevron.right" : item.kind.symbol)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14)).lineLimit(1)
                Text("\(item.source) · \(item.copiedAt.formatted(date: .omitted, time: .shortened))")
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

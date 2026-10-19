import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ClipboardStore
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void

    @FocusState private var searchFocused: Bool
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
        .onAppear { searchFocused = true }
        .onChange(of: store.presentationID) { searchFocused = true }
        .onExitCommand(perform: onDismiss)
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
            Menu {
                Picker("Content type", selection: $store.filter) {
                    ForEach(ClipboardFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol).tag(filter)
                    }
                }
            } label: {
                Label(store.filter.title, systemImage: store.filter.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Filter clipboard history")
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

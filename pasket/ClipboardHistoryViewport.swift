import SwiftUI

struct ClipboardHistoryViewport<Row: View, Footer: View>: View {
    let layout: ClipboardHistoryLayout
    let selectedID: UUID?
    let revision: UUID
    let load: (Range<Int>) async -> Void
    var canLoadBroaderMatches = false
    var isLoadingBroaderMatches = false
    var loadBroaderMatches: () async -> Void = {}
    @ViewBuilder var footer: () -> Footer
    @ViewBuilder var row: (ClipboardHistoryLayout.Entry) -> Row
    @State private var viewport = CGRect(x: 0, y: 0, width: 292, height: 600)
    @State private var position = ScrollPosition(edge: .top)
    @State private var isUserScrolling = false
    @State private var expansionRequested = false

    private struct LoadRequest: Equatable {
        let revision: UUID
        let pages: Range<Int>
    }

    var body: some View {
        let visible = layout.visibleEntries(in: viewport.minY..<viewport.maxY)
        let items = layout.itemRange(in: visible)
        let pageSize = ClipboardHistoryLayout.pageSize
        // Keep task identity stable while moving within the same batch of summaries.
        let pages = items.isEmpty ? 0..<0 : (items.lowerBound / pageSize)..<((items.upperBound - 1) / pageSize + 1)
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(layout.entries[visible])) { entry in
                        row(entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: entry.height)
                            .padding(.horizontal, ClipboardHistoryLayout.inset)
                            .offset(y: entry.y)
                    }
                }
                // Reserve the discovered index independently of loaded summary pages.
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: layout.height, alignment: .topLeading)
                if canLoadBroaderMatches {
                    footer()
                        .frame(height: ClipboardHistoryLayout.rowHeight)
                }
            }
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
            viewport = rect
            if isUserScrolling, rect.maxY >= layout.height { requestExpansion() }
        }
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .interacting || phase == .decelerating
            if phase == .interacting {
                expansionRequested = false
                if viewport.maxY >= layout.height { requestExpansion() }
            }
        }
        .task(id: LoadRequest(revision: revision, pages: pages)) {
            await load((pages.lowerBound * pageSize)..<(pages.upperBound * pageSize))
        }
        .focusable(false)
        .onChange(of: selectedID) {
            if let selectedID,
               let offset = layout.scrollOffset(revealing: selectedID, in: viewport.minY..<viewport.maxY) {
                position.scrollTo(y: offset)
            }
        }
    }

    private func requestExpansion() {
        guard canLoadBroaderMatches, !isLoadingBroaderMatches, !expansionRequested else { return }
        expansionRequested = true
        Task {
            await loadBroaderMatches()
        }
    }
}

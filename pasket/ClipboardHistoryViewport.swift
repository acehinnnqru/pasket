import SwiftUI

struct ClipboardHistoryViewport<Row: View>: View {
    let layout: ClipboardHistoryLayout
    let selectedID: UUID?
    let revision: UUID
    let load: (Range<Int>) async -> Void
    @ViewBuilder var row: (ClipboardHistoryLayout.Entry) -> Row
    @State private var viewport = CGRect(x: 0, y: 0, width: 292, height: 600)
    @State private var position = ScrollPosition(edge: .top)

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
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.entries[visible])) { entry in
                    row(entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: entry.height)
                        .padding(.horizontal, ClipboardHistoryLayout.inset)
                        .offset(y: entry.y)
                }
            }
            // The document height comes from the entire index, never the loaded page count.
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: layout.height, alignment: .topLeading)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
            viewport = rect
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
}

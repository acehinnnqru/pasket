import AppKit
import Observation
import SwiftUI
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ClipboardHistoryViewportTests {
    @Test func nativeScrollbarKeepsItsRangeWhenDistantPlaceholdersLoad() async throws {
        _ = NSApplication.shared
        let model = ViewportFixture()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 292, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: ViewportFixtureView(model: model))
        window.contentView = hosting
        await settle(hosting)
        let scroll = try #require(findScrollView(in: hosting))
        let document = try #require(scroll.documentView)
        #expect(abs(document.bounds.height - model.layout.height) < 1)
        let height = document.bounds.height
        let proportion = try #require(scroll.verticalScroller?.knobProportion)
        #expect(proportion > 0)
        #expect(proportion < 0.02)

        let destination = try #require(model.layout.entry(for: model.references[950].id))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: destination.y))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle(hosting)
        #expect(model.requests.contains { $0.contains(950) })
        #expect(model.requests.allSatisfy { $0.count <= 100 })
        let offset = scroll.documentVisibleRect.minY
        #expect(abs(offset - destination.y) < 1)

        model.loaded = true
        await settle(hosting)
        #expect(document.bounds.height == height)
        #expect(abs(scroll.documentVisibleRect.minY - offset) < 1)
        #expect(scroll.verticalScroller?.knobProportion == proportion)

        // Selection can reveal an offscreen row that has no instantiated view yet.
        model.selectedID = model.references[10].id
        await settle(hosting)
        let selected = try #require(model.layout.entry(for: model.references[10].id))
        #expect(scroll.documentVisibleRect.minY <= selected.y + 1)
        #expect(scroll.documentVisibleRect.maxY >= selected.maxY - 1)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }

    private func settle(_ view: NSView) async {
        for _ in 0..<10 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor @Observable private final class ViewportFixture {
    let references = (0..<1000).map { _ in ClipboardHistoryReference(id: UUID(), copiedAt: .now) }
    var layout: ClipboardHistoryLayout { ClipboardHistoryLayout(references, query: "match") }
    let revision = UUID()
    var selectedID: UUID?
    var loaded = false
    var requests: [Range<Int>] = []
}

private struct ViewportFixtureView: View {
    let model: ViewportFixture

    var body: some View {
        ClipboardHistoryViewport(layout: model.layout, selectedID: model.selectedID, revision: model.revision,
                                 load: { model.requests.append($0) }) { entry in
            Text(model.loaded ? "Loaded history entry" : "Loading history…")
        }
    }
}

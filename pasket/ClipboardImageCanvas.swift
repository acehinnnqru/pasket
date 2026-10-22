import AppKit
import SwiftUI

struct ClipboardImageCanvas: NSViewRepresentable {
    var image: NSImage?

    func makeNSView(context: Context) -> ClipboardImageCanvasView {
        ClipboardImageCanvasView()
    }

    func updateNSView(_ nsView: ClipboardImageCanvasView, context: Context) {
        nsView.setImage(image)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ClipboardImageCanvasView,
                      context: Context) -> CGSize? {
        // The image must not contribute its pixel dimensions to the panel's layout.
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class ClipboardImageCanvasView: NSView {
    private var sourceImage: NSImage?
    private var bitmap: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { return nil }

    func setImage(_ image: NSImage?) {
        guard sourceImage !== image else { return }
        sourceImage = image
        bitmap = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        guard let bitmap, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / CGFloat(bitmap.width), bounds.height / CGFloat(bitmap.height))
        let size = CGSize(width: CGFloat(bitmap.width) * scale, height: CGFloat(bitmap.height) * scale)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        context.interpolationQuality = .high
        context.draw(bitmap, in: rect)
    }
}

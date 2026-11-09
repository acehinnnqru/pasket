import AppKit
import SwiftUI
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ClipboardImageCanvasTests {
    @Test func hostedGIFPreviewChangesFramesWhenThePanelAppears() async throws {
        _ = NSApplication.shared
        let image = try #require(NSImage(data: ClipboardTests.animatedGIF()))
        let panel = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        defer { panel.close() }
        let hosting = NSHostingView(rootView: ClipboardAnimatedImageCanvas(image: image))
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let view = try #require(imageView(in: hosting))
        let bitmap = try #require(view.image?.representations.first as? NSBitmapImageRep)
        let first = try #require(bitmap.value(forProperty: .currentFrame) as? Int)
        let firstColor = try centerBrightness(of: view)
        #expect(!view.animates)

        panel.setShowing(true)
        #expect(view.animates)
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(20))
            if bitmap.value(forProperty: .currentFrame) as? Int != first { break }
        }
        #expect(bitmap.value(forProperty: .currentFrame) as? Int != first)
        #expect(abs(try centerBrightness(of: view) - firstColor) > 0.5)

        panel.setShowing(false)
        #expect(!view.animates)
    }

    private func imageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView { return imageView }
        return view.subviews.lazy.compactMap { imageView(in: $0) }.first
    }

    private func centerBrightness(of view: NSView) throws -> CGFloat {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        return try #require(color?.usingColorSpace(.deviceRGB)).redComponent
    }

    @Test func thinLinesArePresentOnTheFirstDrawAndStableAcrossRedraws() throws {
        let view = ClipboardImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let image = try linedImage()
        view.setImage(image)
        let first = try render(view)
        let line = try #require(first.colorAt(x: 100, y: 120))
        let background = try #require(first.colorAt(x: 110, y: 120))
        #expect(line.alphaComponent == 1)
        #expect(line.redComponent < background.redComponent)
        for _ in 0..<5 {
            view.setImage(image)
            #expect(try pixels(render(view)) == pixels(first))
        }
    }

    @Test func resizingFitsTheImageImmediatelyAndRestoresTheSamePixels() throws {
        let view = ClipboardImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        view.setImage(try linedImage())
        let first = try render(view)
        #expect(try #require(first.colorAt(x: 200, y: 10)).alphaComponent == 0)
        #expect(try #require(first.colorAt(x: 200, y: 30)).alphaComponent == 1)
        view.setFrameSize(NSSize(width: 200, height: 400))
        let resized = try render(view)
        #expect(try #require(resized.colorAt(x: 100, y: 140)).alphaComponent == 0)
        #expect(try #require(resized.colorAt(x: 100, y: 160)).alphaComponent == 1)
        view.setFrameSize(NSSize(width: 400, height: 240))
        let restored = try render(view)
        #expect(try pixels(restored) == pixels(first))
    }

    @Test func clearingTheImageRemovesThePreviousDrawing() throws {
        let view = ClipboardImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        view.setImage(try linedImage())
        let bitmap = try render(view)
        #expect(try #require(bitmap.colorAt(x: 100, y: 120)).alphaComponent == 1)
        view.setImage(nil)
        draw(view, into: bitmap)
        #expect(try #require(bitmap.colorAt(x: 100, y: 120)).alphaComponent == 0)
    }

    @Test(arguments: [1, 2])
    func thumbnailLinesRemainStableWhenRedisplayed(scale: Int) throws {
        let view = ClipboardImageCanvasView(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        let image = try linedImage(width: 60, height: 30, spacing: 6)
        view.setImage(image)
        let first = try render(view, scale: scale)
        let line = try #require(first.colorAt(x: 3 * scale, y: 15 * scale))
        let background = try #require(first.colorAt(x: 5 * scale, y: 15 * scale))
        #expect(line.alphaComponent == 1)
        #expect(line.redComponent < background.redComponent)
        for _ in 0..<5 {
            view.setImage(nil)
            _ = try render(view, scale: scale)
            view.setImage(image)
            #expect(try pixels(render(view, scale: scale)) == pixels(first))
        }
    }

    private func linedImage(width: Int = 800, height: Int = 400, spacing: Int = 40) throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.black.cgColor)
        for x in stride(from: spacing, to: width, by: spacing) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: width, height: height))
    }

    private func render(_ view: ClipboardImageCanvasView, scale: Int = 1) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * scale,
                                                  pixelsHigh: Int(view.bounds.height) * scale, bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        draw(view, into: bitmap, scale: scale)
        return bitmap
    }

    private func draw(_ view: ClipboardImageCanvasView, into bitmap: NSBitmapImageRep, scale: Int = 1) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        view.draw(view.bounds)
    }

    private func pixels(_ bitmap: NSBitmapImageRep) throws -> Data {
        Data(bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}

private final class PreviewPanel: NSPanel {
    private var showing = false
    override var isVisible: Bool { showing }
    override var occlusionState: NSWindow.OcclusionState { showing ? [.visible] : [] }

    func setShowing(_ showing: Bool) {
        self.showing = showing
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }
}

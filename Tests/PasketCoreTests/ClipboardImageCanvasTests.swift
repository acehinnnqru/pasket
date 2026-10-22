import AppKit
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ClipboardImageCanvasTests {
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

    private func linedImage() throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        context.setFillColor(NSColor.black.cgColor)
        for x in stride(from: 40, to: 800, by: 40) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: 400))
        }
        return NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: 800, height: 400))
    }

    private func render(_ view: ClipboardImageCanvasView) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
                                                  pixelsHigh: Int(view.bounds.height), bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        draw(view, into: bitmap)
        return bitmap
    }

    private func draw(_ view: ClipboardImageCanvasView, into bitmap: NSBitmapImageRep) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.draw(view.bounds)
    }

    private func pixels(_ bitmap: NSBitmapImageRep) throws -> Data {
        Data(bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}

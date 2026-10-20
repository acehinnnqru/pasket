import AppKit

enum PasketMenuIcon {
    // Share this monochrome mark across the menu bar, history, settings, and setup.
    // Draw at menu-bar scale rather than tracing the detailed Dock artwork.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()

            let cards = NSBezierPath()
            cards.move(to: NSPoint(x: 4.2, y: 6.9))
            cards.line(to: NSPoint(x: 3.6, y: 3.1))
            cards.curve(to: NSPoint(x: 4.3, y: 2.2),
                        controlPoint1: NSPoint(x: 3.5, y: 2.6), controlPoint2: NSPoint(x: 3.8, y: 2.3))
            cards.line(to: NSPoint(x: 11.2, y: 1.1))
            cards.curve(to: NSPoint(x: 12.1, y: 1.8),
                        controlPoint1: NSPoint(x: 11.7, y: 1.0), controlPoint2: NSPoint(x: 12.0, y: 1.3))
            cards.line(to: NSPoint(x: 12.5, y: 4.0))
            cards.move(to: NSPoint(x: 6.3, y: 6.9))
            cards.line(to: NSPoint(x: 7.0, y: 3.9))
            cards.curve(to: NSPoint(x: 7.9, y: 3.4),
                        controlPoint1: NSPoint(x: 7.1, y: 3.5), controlPoint2: NSPoint(x: 7.5, y: 3.3))
            cards.line(to: NSPoint(x: 14.0, y: 4.8))
            cards.curve(to: NSPoint(x: 14.6, y: 5.7),
                        controlPoint1: NSPoint(x: 14.4, y: 4.9), controlPoint2: NSPoint(x: 14.7, y: 5.3))
            cards.line(to: NSPoint(x: 14.3, y: 6.9))

            let rim = NSBezierPath(roundedRect: NSRect(x: 1.2, y: 7.0, width: 15.6, height: 2.1),
                                   xRadius: 1.0, yRadius: 1.0)
            let basket = NSBezierPath()
            basket.move(to: NSPoint(x: 2.3, y: 9.2))
            basket.line(to: NSPoint(x: 3.6, y: 15.0))
            basket.curve(to: NSPoint(x: 5.3, y: 16.4),
                         controlPoint1: NSPoint(x: 3.8, y: 15.9), controlPoint2: NSPoint(x: 4.3, y: 16.4))
            basket.line(to: NSPoint(x: 12.7, y: 16.4))
            basket.curve(to: NSPoint(x: 14.4, y: 15.0),
                         controlPoint1: NSPoint(x: 13.7, y: 16.4), controlPoint2: NSPoint(x: 14.2, y: 15.9))
            basket.line(to: NSPoint(x: 15.7, y: 9.2))

            let monogram = NSBezierPath()
            monogram.move(to: NSPoint(x: 7.8, y: 14.5))
            monogram.line(to: NSPoint(x: 7.8, y: 10.8))
            monogram.line(to: NSPoint(x: 9.5, y: 10.8))
            monogram.curve(to: NSPoint(x: 9.5, y: 13.0),
                           controlPoint1: NSPoint(x: 11.5, y: 10.8), controlPoint2: NSPoint(x: 11.5, y: 13.0))
            monogram.line(to: NSPoint(x: 7.8, y: 13.0))

            for path in [cards, rim, basket, monogram] {
                path.lineWidth = 1.15
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pasket"
        return image
    }()
}

import AppKit
import QuartzCore
import SwiftUI

struct ClipboardCollectionIndicator: NSViewRepresentable {
    @Environment(\.self) private var environment
    var isCollecting: Bool

    func makeNSView(context: Context) -> IndicatorView {
        IndicatorView()
    }

    func updateNSView(_ nsView: IndicatorView, context: Context) {
        let color: Color = isCollecting ? .accentColor : .secondary
        nsView.update(color: color.resolve(in: environment).cgColor, isCollecting: isCollecting,
                      animates: isCollecting && !environment.accessibilityReduceMotion)
    }

    final class IndicatorView: NSView {
        private let dot = CAShapeLayer()
        private let animationKey = "collectionPulse"
        private var animates = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            let circle = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 7, height: 7), transform: nil)
            dot.bounds = circle.boundingBoxOfPath
            dot.path = circle
            dot.shadowPath = circle
            dot.shadowOffset = .zero
            dot.shadowRadius = 6
            layer?.addSublayer(dot)
        }

        required init?(coder: NSCoder) { return nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            if let window {
                center.addObserver(self, selector: #selector(updateAnimation),
                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            updateAnimation()
        }

        func update(color: CGColor, isCollecting: Bool, animates: Bool) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.fillColor = color
            dot.opacity = isCollecting ? 1 : 0.6
            dot.shadowColor = color
            dot.shadowOpacity = isCollecting ? 0.55 : 0
            CATransaction.commit()
            self.animates = animates
            updateAnimation()
        }

        @objc private func updateAnimation() {
            guard animates, let window, window.isVisible, window.occlusionState.contains(.visible) else {
                dot.removeAnimation(forKey: animationKey)
                return
            }
            guard dot.animation(forKey: animationKey) == nil else { return }

            // Animate layer values so each frame can be composited without laying out SwiftUI views.
            let halfCycle = 1.4
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0.4
            opacity.duration = halfCycle
            let glow = CABasicAnimation(keyPath: "shadowOpacity")
            glow.fromValue = 0.55
            glow.toValue = 0.08
            glow.duration = halfCycle

            let pulse = CAAnimationGroup()
            pulse.animations = [opacity, glow]
            pulse.duration = halfCycle
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dot.add(pulse, forKey: animationKey)
        }
    }
}

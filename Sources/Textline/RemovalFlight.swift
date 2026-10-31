import AppKit
import QuartzCore

/// The snapshot keeps its size and slides right out of the sidebar viewport.
@MainActor final class RemovalFlight {
    private static var active: [RemovalFlight] = []
    private let window: NSPanel
    private let layer = CALayer()
    private let card: CGRect
    private var started: CFTimeInterval = 0
    private var timer: Timer?
    private let duration = 0.28
    static var activeCount: Int { active.count }
    static func cancelAll() {
        for flight in active { flight.timer?.invalidate(); flight.timer = nil; flight.window.orderOut(nil) }
        active.removeAll()
    }

    static func slide(image: CGImage, card: CGRect, screen: NSScreen, viewport: CGRect) {
        let flight = RemovalFlight(image: image, card: card, screen: screen, viewport: viewport)
        active.append(flight)
        flight.start()
    }
    private init(image: CGImage, card: CGRect, screen: NSScreen, viewport: CGRect) {
        self.card = card
        window = NSPanel(contentRect: viewport, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .init(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSView(frame: NSRect(origin: .zero, size: viewport.size))
        host.wantsLayer = true; host.layer?.masksToBounds = true; window.contentView = host
        layer.contents = image; layer.contentsScale = screen.backingScaleFactor
        layer.bounds = CGRect(origin: .zero, size: card.size)
        layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        host.layer?.addSublayer(layer)
    }
    private func start() {
        update(0); window.orderFrontRegardless(); started = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        let progress = min(1, (CACurrentMediaTime() - started) / duration)
        update(progress)
        if progress >= 1 {
            timer?.invalidate(); timer = nil; window.orderOut(nil)
            Self.active.removeAll { $0 === self }
        }
    }
    private func update(_ progress: Double) {
        let e = CGFloat(1 - pow(1 - progress, 3))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let startX = card.minX - window.frame.minX
        let endX = window.frame.width + 12
        layer.position = CGPoint(x: startX + (endX - startX) * e, y: card.midY - window.frame.minY)
        layer.setAffineTransform(.identity)
        layer.opacity = 1
        CATransaction.commit()
    }
}

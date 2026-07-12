import AppKit
import Observation

@Observable
@MainActor
final class RulerGuideController {
    static let shared = RulerGuideController()

    private(set) var isVisible = false
    private(set) var verticalGuides: [CGFloat] = []
    private(set) var horizontalGuides: [CGFloat] = []
    private var panels: [NSPanel] = []
    private var timer: Timer?

    private init() {}

    func toggleCrosshair() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = RulerGuideView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
            panel.orderFrontRegardless()
            return panel
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 1 / 120
        refresh()
    }

    func hide() {
        isVisible = false
        timer?.invalidate()
        timer = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    func pinGuidesAtPointer() {
        let point = NSEvent.mouseLocation
        verticalGuides.append(point.x)
        horizontalGuides.append(point.y)
        if !isVisible { show() }
        refresh()
    }

    func clearGuides() {
        verticalGuides.removeAll()
        horizontalGuides.removeAll()
        refresh()
    }

    private func refresh() {
        let pointer = NSEvent.mouseLocation
        for panel in panels {
            (panel.contentView as? RulerGuideView)?.update(
                pointer: pointer,
                verticalGuides: verticalGuides,
                horizontalGuides: horizontalGuides
            )
        }
    }
}

private final class RulerGuideView: NSView {
    private let screenFrame: CGRect
    private var pointer = CGPoint.zero
    private var verticalGuides: [CGFloat] = []
    private var horizontalGuides: [CGFloat] = []

    init(frame: CGRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    func update(pointer: CGPoint, verticalGuides: [CGFloat], horizontalGuides: [CGFloat]) {
        self.pointer = pointer
        self.verticalGuides = verticalGuides
        self.horizontalGuides = horizontalGuides
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.72).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        if screenFrame.contains(pointer) {
            path.move(to: CGPoint(x: pointer.x - screenFrame.minX, y: bounds.minY))
            path.line(to: CGPoint(x: pointer.x - screenFrame.minX, y: bounds.maxY))
            path.move(to: CGPoint(x: bounds.minX, y: pointer.y - screenFrame.minY))
            path.line(to: CGPoint(x: bounds.maxX, y: pointer.y - screenFrame.minY))
        }
        for x in verticalGuides where screenFrame.minX...screenFrame.maxX ~= x {
            path.move(to: CGPoint(x: x - screenFrame.minX, y: bounds.minY))
            path.line(to: CGPoint(x: x - screenFrame.minX, y: bounds.maxY))
        }
        for y in horizontalGuides where screenFrame.minY...screenFrame.maxY ~= y {
            path.move(to: CGPoint(x: bounds.minX, y: y - screenFrame.minY))
            path.line(to: CGPoint(x: bounds.maxX, y: y - screenFrame.minY))
        }
        path.stroke()
    }
}

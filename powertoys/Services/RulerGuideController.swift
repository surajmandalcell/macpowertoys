import AppKit
import Observation

@Observable
@MainActor
final class RulerGuideController {
    static let shared = RulerGuideController()

    private(set) var isVisible = false
    private(set) var isEditing = false
    private(set) var verticalGuides: [CGFloat] = []
    private(set) var horizontalGuides: [CGFloat] = []
    private var panels: [NSPanel] = []
    private var editPanel: NSPanel?
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
            panel.contentView = RulerGuideView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame, controller: self)
            panel.orderFrontRegardless()
            return panel
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.refresh() }
        }
        timer?.tolerance = 1 / 120
        refresh()
    }

    func hide() {
        isVisible = false
        isEditing = false
        timer?.invalidate()
        timer = nil
        panels.forEach { $0.close() }
        panels.removeAll()
        editPanel?.close()
        editPanel = nil
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

    func toggleEditing() {
        guard !verticalGuides.isEmpty || !horizontalGuides.isEmpty else { return }
        isEditing.toggle()
        panels.forEach { $0.ignoresMouseEvents = !isEditing }
        if isEditing { showEditPanel() }
        else {
            editPanel?.close()
            editPanel = nil
        }
    }

    func moveVerticalGuide(at index: Int, to x: CGFloat) {
        guard verticalGuides.indices.contains(index) else { return }
        verticalGuides[index] = x
        refresh()
    }

    func moveHorizontalGuide(at index: Int, to y: CGFloat) {
        guard horizontalGuides.indices.contains(index) else { return }
        horizontalGuides[index] = y
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

    private func showEditPanel() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 150, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let button = NSButton(title: "Done Editing Guides", target: self, action: #selector(finishEditing))
        button.bezelStyle = .rounded
        button.frame = CGRect(x: 8, y: 6, width: 134, height: 28)
        panel.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 150, height: 40))
        panel.contentView?.addSubview(button)
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - 75, y: visible.maxY - 52))
        }
        panel.orderFrontRegardless()
        editPanel = panel
    }

    @objc private func finishEditing() {
        if isEditing { toggleEditing() }
    }
}

private final class RulerGuideView: NSView {
    private enum DragTarget { case vertical(Int), horizontal(Int) }
    private let screenFrame: CGRect
    private weak var controller: RulerGuideController?
    private var pointer = CGPoint.zero
    private var verticalGuides: [CGFloat] = []
    private var horizontalGuides: [CGFloat] = []
    private var dragTarget: DragTarget?

    init(frame: CGRect, screenFrame: CGRect, controller: RulerGuideController) {
        self.screenFrame = screenFrame
        self.controller = controller
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

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let global = CGPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
        if let match = verticalGuides.enumerated().min(by: { abs($0.element - global.x) < abs($1.element - global.x) }),
           abs(match.element - global.x) <= 8 {
            dragTarget = .vertical(match.offset)
        } else if let match = horizontalGuides.enumerated().min(by: { abs($0.element - global.y) < abs($1.element - global.y) }),
                  abs(match.element - global.y) <= 8 {
            dragTarget = .horizontal(match.offset)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        switch dragTarget {
        case .vertical(let index): controller?.moveVerticalGuide(at: index, to: local.x + screenFrame.minX)
        case .horizontal(let index): controller?.moveHorizontalGuide(at: index, to: local.y + screenFrame.minY)
        case nil: break
        }
    }

    override func mouseUp(with event: NSEvent) { dragTarget = nil }
}

import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

/// The drag math, then the real Forward cards driven by mouse events in an offscreen window: a drag reorders
/// host cards and forwards, a plain click still reaches the buttons. Set PORTMAN_SHOT_DIR to save the 2x PNGs.
@MainActor
final class PortmanReorderTests: XCTestCase {
    // MARK: Drag math

    /// Three 40 pt rows with a 10 pt gap: middles at 20, 70, 120.
    private func drag(source: Int, by translation: CGFloat) -> PortmanDrag {
        PortmanDrag(frames: [0: CGRect(x: 0, y: 0, width: 100, height: 40), 1: CGRect(x: 0, y: 50, width: 100, height: 40),
                             2: CGRect(x: 0, y: 100, width: 100, height: 40)],
                    source: source, translation: translation)
    }

    func testTargetFollowsTheMiddleOfTheDraggedRow() {
        XCTAssertEqual(drag(source: 0, by: 0).target(movable: 3), 0)
        XCTAssertEqual(drag(source: 0, by: 49).target(movable: 3), 0, "still above the next middle")
        XCTAssertEqual(drag(source: 0, by: 51).target(movable: 3), 1)
        XCTAssertEqual(drag(source: 0, by: 500).target(movable: 3), 2, "past the end clamps to last")
        XCTAssertEqual(drag(source: 2, by: -500).target(movable: 3), 0, "past the top clamps to first")
        XCTAssertEqual(drag(source: 0, by: 500).target(movable: 2), 1, "rows past `movable` never take a drop")
        XCTAssertNil(drag(source: 2, by: 0).target(movable: 2), "an unsaved row never drags")
        XCTAssertNil(PortmanDrag().target(movable: 3))
    }

    func testOthersSlideOneSlotAndTheLineMarksTheGap() {
        let down = drag(source: 0, by: 120)
        XCTAssertEqual(down.offset(of: 0, movable: 3, spacing: 10), 120)
        XCTAssertEqual(down.offset(of: 1, movable: 3, spacing: 10), -50)
        XCTAssertEqual(down.offset(of: 2, movable: 3, spacing: 10), -50)
        XCTAssertEqual(down.indicator(movable: 3, spacing: 10), 95, "gap between the moved-up row 2 and the slot")
        let up = drag(source: 2, by: -100)
        XCTAssertEqual(up.offset(of: 0, movable: 3, spacing: 10), 50)
        XCTAssertEqual(up.offset(of: 1, movable: 3, spacing: 10), 50)
        XCTAssertEqual(up.indicator(movable: 3, spacing: 10), -5, "above the first row")
        XCTAssertNil(drag(source: 1, by: 10).indicator(movable: 3, spacing: 10), "no line while it would land in place")
        XCTAssertEqual(drag(source: 1, by: 10).offset(of: 0, movable: 3, spacing: 10), 0)
    }

    // MARK: Real cards, real mouse events

    private let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 400, height: 400), styleMask: .borderless,
                                  backing: .buffered, defer: false)
    private var suite = ""
    private var calls: [String] = []

    override func tearDown() async throws {
        window.close()
        if !suite.isEmpty { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }

    private func makeList() -> PortmanHostList {
        suite = "portman-reorder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        PortmanHostStore.save([
            PortmanHost(destination: "build-box", mode: .forward, forwards: [.init(remotePort: 5432, localPort: 5432),
                                                                             .init(remotePort: 9000, localPort: 9000)]),
            PortmanHost(destination: "staging-eu", mode: .forward, forwards: [.init(remotePort: 8000, localPort: 8000),
                                                                              .init(remotePort: 80, localPort: 8080)]),
            PortmanHost(destination: "gpu-lab", mode: .forward, forwards: [.init(remotePort: 8888, localPort: 8888)]),
        ], defaults)
        return PortmanHostList(defaults: defaults)
    }

    private func show(_ list: PortmanHostList, appearance: NSAppearance.Name = .aqua, drag: PortmanDrag = PortmanDrag()) -> NSHostingView<Harness> {
        let host = NSHostingView(rootView: Harness(list: list, log: { [weak self] in self?.calls.append($0) }, drag: drag))
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = CGRect(origin: .zero, size: size)
        // SwiftUI hit-tests only an ordered-in window. It sits 10000 pt off every screen and never becomes key,
        // so the app stays in the background and the owner's front app keeps focus.
        window.orderFrontRegardless()
        settle()
        return host
    }

    private func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Top-left view points to window points; the hosting view is flipped from the window's bottom-left origin.
    private func send(_ type: NSEvent.EventType, _ point: CGPoint) {
        let height = window.contentView?.bounds.height ?? 0
        let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: height - point.y), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        window.sendEvent(try! XCTUnwrap(event))
        settle(0.02)
    }

    private func press(from start: CGPoint, by dy: CGFloat, release: Bool = true) {
        send(.leftMouseDown, start)
        let steps = 12
        for step in 1...steps { send(.leftMouseDragged, CGPoint(x: start.x, y: start.y + dy * CGFloat(step) / CGFloat(steps))) }
        if release {
            send(.leftMouseUp, CGPoint(x: start.x, y: start.y + dy))
            settle(0.4)
        }
    }

    private func click(_ point: CGPoint) {
        send(.leftMouseDown, point)
        send(.leftMouseUp, point)
        settle(0.1)
    }

    /// Card tops for three closed cards with 2, 2, and 1 forwards.
    private var layout: (cardTops: [CGFloat], rowHeight: CGFloat, childHeight: CGFloat) {
        let pad = Harness.inset, list: CGFloat = 4, row = OnePlusLinearMetrics.panelTwoLineRow, child = OnePlusLinearMetrics.treeChildRow
        let gap = OnePlusLinearPanelStyle.fillSteps.blockGap
        let heights = [2, 2, 1].map { list * 2 + row + CGFloat($0) * child }
        var tops: [CGFloat] = [], y = pad
        for height in heights { tops.append(y); y += height + gap }
        return (tops, row, child)
    }

    func testDraggingAHostCardReordersAndSaves() {
        let list = makeList()
        _ = show(list)
        let top = layout.cardTops
        // Grab build-box's caption area (inside its toggle button) and drop it below gpu-lab.
        press(from: CGPoint(x: 120, y: top[0] + 4 + 20), by: top[2] - top[0] + 60)
        XCTAssertEqual(list.hosts.map(\.destination), ["staging-eu", "gpu-lab", "build-box"])
        XCTAssertFalse(calls.contains("toggle build-box"), "a drag is not a click")
        XCTAssertEqual(PortmanHostList(defaults: UserDefaults(suiteName: suite)!).hosts.map(\.destination),
                       ["staging-eu", "gpu-lab", "build-box"])
    }

    func testDraggingAForwardStaysInsideItsCard() {
        let list = makeList()
        _ = show(list)
        let (top, row, child) = layout
        // staging-eu's first forward (8000) down one row, then far past the card: it lands last in its own card.
        let firstChild = CGPoint(x: 160, y: top[1] + 4 + row + child / 2)
        press(from: firstChild, by: child * 1.2)
        XCTAssertEqual(list.host("staging-eu")?.forwards.map(\.localPort), [8080, 8000])
        press(from: CGPoint(x: 160, y: top[1] + 4 + row + child * 1.5), by: -400)
        XCTAssertEqual(list.host("staging-eu")?.forwards.map(\.localPort), [8000, 8080])
        XCTAssertEqual(list.hosts.map(\.destination), ["build-box", "staging-eu", "gpu-lab"], "the card did not move")
        XCTAssertEqual(list.host("build-box")?.forwards.map(\.localPort), [5432, 9000])
    }

    func testClicksStillReachTheButtons() {
        let list = makeList()
        _ = show(list)
        let (top, row, child) = layout
        click(CGPoint(x: 120, y: top[0] + 4 + row / 2))
        XCTAssertTrue(calls.contains("toggle build-box"), "host row click toggles the charts: \(calls)")
        let width = window.contentView?.bounds.width ?? 0
        let icon = CGPoint(x: width - Harness.inset - OnePlusLinearMetrics.panelRowInset - OnePlusLinearMetrics.panelAccessory / 2,
                           y: top[0] + 4 + row + child / 2)
        click(icon)
        XCTAssertTrue(calls.contains("retry 5432"), "the stopped forward's re-forward key: \(calls)")
        click(CGPoint(x: icon.x, y: top[0] + 4 + row / 2))
        XCTAssertTrue(calls.contains("retry all"), "the host row's Reconnect all key: \(calls)")
        XCTAssertEqual(list.hosts.map(\.destination), ["build-box", "staging-eu", "gpu-lab"])
    }

    func testVoiceOverMoveActions() throws {
        let list = makeList()
        let host = show(list)
        let (top, row, child) = layout
        // SwiftUI builds its tree on demand: hit-test a point, then walk up to the element with the label.
        func value(_ node: NSObject, _ name: String) -> Any? { node.responds(to: NSSelectorFromString(name)) ? node.value(forKey: name) : nil }
        func element(at point: CGPoint, _ label: String) -> NSObject? {
            let height = window.contentView?.bounds.height ?? 0
            var node = host.accessibilityHitTest(window.convertPoint(toScreen: CGPoint(x: point.x, y: height - point.y))) as? NSObject
            while let current = node {
                if value(current, "accessibilityLabel") as? String == label { return current }
                node = value(current, "accessibilityParent") as? NSObject
            }
            return nil
        }
        func customActions(_ element: NSObject) -> [NSAccessibilityCustomAction] {
            value(element, "accessibilityCustomActions") as? [NSAccessibilityCustomAction] ?? []
        }
        func actions(_ element: NSObject) -> [String] { customActions(element).map(\.name).sorted() }
        func perform(_ name: String, on element: NSObject) throws {
            let action = try XCTUnwrap(customActions(element).first { $0.name == name })
            if let handler = action.handler { XCTAssertTrue(handler()) } else { _ = (action.target as? NSObject)?.perform(action.selector, with: action) }
        }
        let card = try XCTUnwrap(element(at: CGPoint(x: 120, y: top[1] + 4 + row / 2), "staging-eu"))
        XCTAssertEqual(actions(card), ["Move down", "Move up"])
        let first = try XCTUnwrap(element(at: CGPoint(x: 160, y: top[0] + 4 + row + child / 2), "build-box"))
        XCTAssertEqual(actions(first), ["Move down"])
        let forward = try XCTUnwrap(element(at: CGPoint(x: 160, y: top[1] + 4 + row + child / 2), "localhost:8000"))
        XCTAssertEqual(actions(forward), ["Move down"])
        let lone = try XCTUnwrap(element(at: CGPoint(x: 160, y: top[2] + 4 + row + child / 2), "localhost:8888"))
        XCTAssertEqual(actions(lone), [], "a lone forward has nothing to move past")
        try perform("Move down", on: forward)
        try perform("Move up", on: card)
        settle(0.3)
        XCTAssertEqual(list.hosts.map(\.destination), ["staging-eu", "build-box", "gpu-lab"])
        XCTAssertEqual(list.host("staging-eu")?.forwards.map(\.localPort), [8080, 8000])
    }

    // MARK: Shots

    func testShotsMidDragAndAfter() throws {
        let directory = ProcessInfo.processInfo.environment["PORTMAN_SHOT_DIR"]
        let (top, row, child) = layout
        let heights = [2, 2, 1].map { 8 + row + CGFloat($0) * child }
        let frames = Dictionary(uniqueKeysWithValues: (0..<3).map {
            ($0, CGRect(x: 0, y: top[$0] - Harness.inset, width: OnePlusLinearMetrics.panelWidth - Harness.inset * 2, height: heights[$0]))
        })
        // An offscreen window gets no display frames, so a live drag never repaints; seed one frame of it instead.
        let midDrag = PortmanDrag(frames: frames, source: 0, translation: top[1] - top[0] + 12)
        XCTAssertEqual(midDrag.target(movable: 3), 1)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try save(show(makeList(), appearance: appearance, drag: midDrag), directory, "reorder-mid-drag-\(name)")
            let list = makeList()
            let host = show(list, appearance: appearance)
            press(from: CGPoint(x: 120, y: top[0] + 24), by: top[2] - top[0] + 30)
            XCTAssertEqual(list.hosts.map(\.destination), ["staging-eu", "gpu-lab", "build-box"])
            try save(host, directory, "reorder-after-\(name)")
            window.contentView = nil
        }
    }

    private func save(_ host: NSView, _ directory: String?, _ name: String) throws {
        let size = host.bounds.size
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let directory else { return }
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}

/// The panel's host stack and cards with closed charts and no live tunnels (every forward Stopped).
private struct Harness: View {
    static let inset = OnePlusLinearMetrics.panelBodyInset
    static let now = Date(timeIntervalSince1970: 1_000_000)
    static let online: PortmanServerState = {
        let samples = (0..<20).map { index in
            PortmanServerSample(date: now.addingTimeInterval(Double(index - 19) * 2), cpuPercent: 20 + sin(Double(index) * 0.6) * 12,
                                memoryUsed: 6 << 30, memoryTotal: 16 << 30, diskUsed: 40_000_000_000, diskTotal: 80_000_000_000,
                                load: [0.42], uptime: 12 * 86_400, receiveRate: 900_000, sendRate: 240_000)
        }
        return PortmanServerState(status: .online, latest: samples.last, history: samples, lastSeen: now)
    }()
    let list: PortmanHostList
    let log: (String) -> Void
    var drag = PortmanDrag()

    var body: some View {
        let groups = PortmanForwardTree.groups(hosts: list.hosts, tunnels: [])
        PortmanReorderStack(items: groups, movable: groups.filter(\.saved).count, spacing: OnePlusLinearPanelStyle.fillSteps.blockGap,
                            name: \.host.destination, move: { list.moveHost($0.host.destination, to: $1) }, drag: drag) { group, _ in
            let destination = group.host.destination
            PortmanHostCard(group: group, model: PortmanHostCardModel(monitors: true, forwards: group.children.count,
                                                                       state: Self.online, now: Self.now),
                            expanded: false, actions: PortmanHostCardActions(
                                toggleStats: { log("toggle \(destination)") },
                                retry: { log("retry \($0.map { String($0.spec.localPort) } ?? "all")") },
                                move: { list.moveForward(host: destination, localPort: $0.spec.localPort, to: $1) }))
        }
        .padding(Self.inset)
        .frame(width: OnePlusLinearMetrics.panelWidth)
        .background(OnePlusLinearColor.fillShell)
        .portmanForwardLook()
        .environment(\.onePlusLinearPanelStyle, .fillSteps)
        .onePlusDensity(.compact)
    }
}

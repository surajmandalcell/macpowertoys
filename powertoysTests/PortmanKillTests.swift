import AppKit
import SwiftUI
import XCTest
import OnePlusUI
@testable import powertoys

/// The kill key rules, the five minute Home rule, and offscreen renders of the Forward placeholder and the server
/// detail kill keys. Set TEST_RUNNER_PORTMAN_SHOT_DIR to save the PNGs.
@MainActor
final class PortmanKillTests: XCTestCase {
    func testKillIsBlockedForSystemAndOwnProcesses() {
        let me = geteuid()
        XCTAssertNotNil(PortmanKill.blockReason(pid: 1, command: "launchd", userID: 0, currentUser: me))
        XCTAssertNotNil(PortmanKill.blockReason(pid: 0, command: "kernel_task", userID: 0, currentUser: me))
        XCTAssertNotNil(PortmanKill.blockReason(pid: 400, command: "WindowServer", userID: me, currentUser: me))
        XCTAssertNotNil(PortmanKill.blockReason(pid: 401, command: "loginwindow", userID: me, currentUser: me))
        XCTAssertNotNil(PortmanKill.blockReason(pid: 500, command: "node", userID: me, ownPID: 500, currentUser: me))
        XCTAssertNotNil(PortmanKill.blockReason(pid: 600, command: "postgres", userID: me + 1, currentUser: me))
        XCTAssertNil(PortmanKill.blockReason(pid: 700, command: "Pumble", userID: me, ownPID: 500, currentUser: me))
    }

    func testKillParentIsBlockedWhenTheParentIsLaunchdOrThisApp() throws {
        XCTAssertNotNil(PortmanKill.blockReason(PortmanKill.Target(pid: 1, command: "launchd", started: 0, userID: 0)))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        let parent = try XCTUnwrap(PortmanKill.parent(of: child.processIdentifier))
        XCTAssertEqual(parent.pid, getpid())
        XCTAssertEqual(PortmanKill.blockReason(parent), "This is MacPowerToys itself")
    }

    func testPanelOpensOnServersAfterFiveMinutesClosed() {
        let now = Date()
        typealias Panel = PortmanPanelView
        XCTAssertEqual(Panel.startPage(saved: .forward, lastClosed: now.addingTimeInterval(-60), now: now), .forward)
        XCTAssertEqual(Panel.startPage(saved: .forward, lastClosed: now.addingTimeInterval(-Panel.homeAfterClosed - 1), now: now), .local)
        XCTAssertEqual(Panel.startPage(saved: .forward, lastClosed: nil, now: now), .local)
        XCTAssertEqual(Panel.startPage(saved: nil, lastClosed: now, now: now), .local)
    }

    func testRenderPlaceholderAndKillKeys() async throws {
        let directory = ProcessInfo.processInfo.environment["PORTMAN_SHOT_DIR"]
        let listener = Process()
        listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        listener.arguments = ["-l", "127.0.0.1", "9613"]
        listener.standardInput = Pipe()
        listener.standardOutput = FileHandle.nullDevice
        try listener.run()
        defer { listener.terminate() }
        let service = PortmanService.shared
        service.beginMonitoring()
        defer { service.endMonitoring() }
        var port: PortmanLocalPort?
        for _ in 0..<20 where port == nil {
            await service.refreshLocal()
            port = service.localPorts.first { $0.pid == listener.processIdentifier }
            if port == nil { try await Task.sleep(for: .milliseconds(250)) }
        }
        let observed = try XCTUnwrap(port)

        let hosts = [PortmanHost(destination: "build-box", mode: .both,
                                 forwards: [.init(remotePort: 5432, localPort: 5432), .init(remotePort: 9000, localPort: 9000)])]
        let tunnels = [PortmanTunnel(id: UUID(), host: "build-box", remotePort: 5432, localPort: 5432, state: .running),
                       PortmanTunnel(id: UUID(), host: "build-box", remotePort: 9000, localPort: 9000, state: .running)]
        let group = try XCTUnwrap(PortmanForwardTree.groups(hosts: hosts, tunnels: tunnels).first)
        let skeleton = VStack(spacing: OnePlusLinearPanelStyle.fillSteps.blockGap) {
            OnePlusLinearTreeCardPlaceholder(children: 2)
            PortmanHostCard(group: group, model: PortmanHostCardModel(monitors: true, forwards: 2, state: nil, now: Date()),
                            expanded: false, actions: PortmanHostCardActions())
        }
        .padding(OnePlusLinearMetrics.panelBodyInset)
        .frame(width: OnePlusLinearMetrics.panelWidth)
        .background(OnePlusLinearColor.fillShell)
        .portmanForwardLook()
        .environment(\.onePlusLinearPanelStyle, .fillSteps)
        .onePlusDensity(.compact)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try save(AnyView(skeleton), "forward-placeholder-\(name)", appearance, directory)
            try save(AnyView(PortmanPanelView(initialPortID: observed.id).background(OnePlusLinearColor.fillShell)
                .environment(\.colorScheme, name == "dark" ? .dark : .light)),
                     "detail-kill-\(name)", appearance, directory)
        }
    }

    private func save(_ view: AnyView, _ name: String, _ appearance: NSAppearance.Name, _ directory: String?) throws {
        let saved = NSApp.appearance
        NSApp.appearance = NSAppearance(named: appearance)
        defer { NSApp.appearance = saved }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 400, height: 600), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let directory else { return }
        try bitmap.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}

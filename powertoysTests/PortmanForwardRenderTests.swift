import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

/// Renders the real Forward tab parts offscreen with fake hosts (build-box healthy, staging-eu with one broken
/// forward, gpu-lab offline) in Light and Dark at 2x. Run with TEST_RUNNER_PORTMAN_SHOT_DIR set to save the PNGs.
@MainActor
final class PortmanForwardRenderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func history(seed: Double, cpu: Double, memory: Double) -> [PortmanServerSample] {
        (0..<60).map { index in
            let i = Double(index)
            let wave = sin(i * 0.21 + seed) * 0.5 + sin(i * 0.57 + seed * 2) * 0.3
            return PortmanServerSample(date: now.addingTimeInterval((i - 59) * 2), cpuPercent: max(1, cpu + wave * 30),
                                       memoryUsed: UInt64((memory + wave * 0.4) * 1_073_741_824), memoryTotal: 16 << 30,
                                       diskUsed: UInt64((40.2 + i * 0.013) * 1_000_000_000), diskTotal: 80_000_000_000,
                                       load: [0.42], uptime: 12 * 86_400,
                                       receiveRate: max(0, 900_000 + wave * 700_000), sendRate: max(0, 240_000 + wave * 120_000))
        }
    }

    private func tunnel(_ host: String, _ local: UInt16, _ remote: UInt16? = nil, _ state: PortmanTunnel.State) -> PortmanTunnel {
        PortmanTunnel(id: UUID(), host: host, remotePort: remote ?? local, localPort: local, state: state)
    }

    private var body: some View {
        let hosts = [
            PortmanHost(destination: "build-box", mode: .both, forwards: [.init(remotePort: 5432, localPort: 5432), .init(remotePort: 9000, localPort: 9000)]),
            PortmanHost(destination: "staging-eu", mode: .both, forwards: [.init(remotePort: 8000, localPort: 8000), .init(remotePort: 80, localPort: 8080)]),
            PortmanHost(destination: "gpu-lab", mode: .both, forwards: [.init(remotePort: 8888, localPort: 8888)]),
        ]
        let tunnels = [
            tunnel("build-box", 5432, nil, .running), tunnel("build-box", 9000, nil, .running),
            tunnel("staging-eu", 8000, nil, .running), tunnel("staging-eu", 8080, 80, .failed("bind [127.0.0.1]:8080: Address already in use")),
            tunnel("gpu-lab", 8888, nil, .failed("ssh: connect to host gpu-lab port 22: Operation timed out")),
        ]
        let build = history(seed: 2, cpu: 23, memory: 9.8), staging = history(seed: 5, cpu: 8, memory: 3.0)
        let states: [String: PortmanServerState] = [
            "build-box": PortmanServerState(status: .online, latest: build.last, history: build, lastSeen: now),
            "staging-eu": PortmanServerState(status: .online, latest: staging.last, history: staging, lastSeen: now),
            "gpu-lab": PortmanServerState(status: .failed(.offline), lastSeen: now.addingTimeInterval(-180)),
        ]
        let groups = PortmanForwardTree.groups(hosts: hosts, tunnels: tunnels)
        return VStack(spacing: OnePlusLinearPanelStyle.fillSteps.blockGap) {
            PortmanForwardInputs(host: .constant("build-box"), manualPort: .constant(""), mode: .constant(.both),
                                 aliases: ["build-box", "staging-eu", "gpu-lab"], scanning: false,
                                 scan: {}, cancel: {}, addPort: {}, addHost: {})
            ForEach(groups) { group in
                PortmanHostCard(group: group, model: PortmanHostCardModel(monitors: true, forwards: group.children.count,
                                                                           state: states[group.id], now: self.now),
                                expanded: group.id == "build-box", actions: PortmanHostCardActions())
            }
        }
        .padding(OnePlusLinearMetrics.panelBodyInset)
        .frame(width: OnePlusLinearMetrics.panelWidth)
        .background(OnePlusLinearColor.fillShell)
        .portmanForwardLook()
        .environment(\.onePlusLinearPanelStyle, .fillSteps)
        .onePlusDensity(.compact)
    }

    func testForwardCardsRenderInBothAppearances() throws {
        let directory = ProcessInfo.processInfo.environment["PORTMAN_SHOT_DIR"]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: body)
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 400, height: 400), styleMask: .borderless,
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
            XCTAssertGreaterThan(size.height, 300)
            if let directory {
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("forward-\(name).png"))
            }
        }
    }
}

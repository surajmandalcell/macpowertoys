//
//  DemoPortman.swift
//  powertoys
//

#if MPT_DEMO
import AppKit

@MainActor
enum DemoPortman {
    /// `project` nil means no git project: the row is named by its app or bare command.
    private struct Server {
        let project: String?
        let branch: String?
        let port: UInt16
        let argv: [String]
        var title: String?
        var executable = ""
        var app: String?
        var environment: PortmanLaunchEnvironment?
        var startedByApp: String?
        let uptime: String
        let upSeconds: Double
        let memoryMB: Double
        let cpuPercent: Double
        let pid: Int32
    }

    private static let orca = "/Applications/Orca.app"
    private static let iTerm = "/Applications/iTerm.app"
    private static let raycast = "/Applications/Raycast.app"

    private static let servers = [
        Server(project: "storefront", branch: "cart", port: 5173,
               argv: ["node", "/Users/demo/dev/storefront/node_modules/.bin/vite"],
               environment: PortmanLaunchEnvironment(claudeCode: true, npmEvent: "dev"), startedByApp: orca,
               uptime: "2h 14m", upSeconds: 8_040, memoryMB: 168.3, cpuPercent: 4.6, pid: 44_386),
        Server(project: "web", branch: "main", port: webPort,
               argv: ["node", "/Users/demo/dev/web/node_modules/.bin/next", "dev"],
               environment: PortmanLaunchEnvironment(npmEvent: "dev"), startedByApp: iTerm,
               uptime: "1m", upSeconds: 60, memoryMB: webPeakMB, cpuPercent: webPeakCPU, pid: 53_640),
        Server(project: "docs", branch: "pricing", port: 4321,
               argv: ["node", "/Users/demo/dev/docs/node_modules/.bin/astro", "dev"],
               environment: PortmanLaunchEnvironment(codex: true), startedByApp: orca,
               uptime: "26m", upSeconds: 1_560, memoryMB: 96.8, cpuPercent: 0.8, pid: 51_907),
        Server(project: "api", branch: "main", port: 8080, argv: ["node", "--watch", "server.js"],
               environment: PortmanLaunchEnvironment(termProgram: "Apple_Terminal"),
               uptime: "5h 02m", upSeconds: 18_120, memoryMB: 38.6, cpuPercent: 1.2, pid: 39_254),
        Server(project: nil, branch: nil, port: 6379, argv: ["redis-server", "/opt/homebrew/etc/redis.conf"],
               uptime: "3d 4h", upSeconds: 274_000, memoryMB: 12.9, cpuPercent: 0.3, pid: 1_018),
        Server(project: "ml", branch: "eval", port: 8000, argv: ["python3", "-m", "uvicorn", "app:main", "--reload"],
               environment: PortmanLaunchEnvironment(codex: true), startedByApp: orca,
               uptime: "6h 40m", upSeconds: 24_000, memoryMB: 412.7, cpuPercent: 0.4, pid: 2_207),
        Server(project: nil, branch: nil, port: forwardPort,
               argv: ["ssh", "-N", "-L", "\(forwardPort):localhost:\(forwardPort)", forwardHost],
               uptime: "48m", upSeconds: 2_880, memoryMB: 7.4, cpuPercent: 0.1, pid: 50_311),
        Server(project: nil, branch: nil, port: 7265, argv: ["Raycast Backend"], title: "Raycast Backend",
               executable: "\(raycast)/Contents/MacOS/Raycast Backend", app: raycast,
               uptime: "1d 2h", upSeconds: 93_600, memoryMB: 84.1, cpuPercent: 0.6, pid: 712),
    ]

    private static let webPort: UInt16 = 3000
    private static let webStartMB = 142.0
    private static let webPeakMB = 781.4
    private static let webStartCPU = 6.0
    private static let webPeakCPU = 38.5
    private static let bytesPerMB = 1_048_576.0
    private static let historySamples = 12
    private static let historySpacing: TimeInterval = 50
    private static let historyWobble = 0.03
    private static let climbStart = 0.6
    private static let climbDuration = 2.6
    private static let climbSteps = 14
    private static let stopAt = 4.4
    private static let forwardHost = "build-box"
    private static let forwardPort: UInt16 = 5432
    private static let otherHosts = ["gpu-lab", "staging-eu"]

    static func seed() { seed(webMB: webPeakMB, webCPU: webPeakCPU) }

    static let scanPortsNotification = Notification.Name("MPTDemoPortmanScanPorts")
    static let remotePorts = [
        PortmanRemotePort(port: 22, processName: "sshd", pid: 812),
        PortmanRemotePort(port: 80, processName: "nginx", pid: 1_204),
        PortmanRemotePort(port: 3000, processName: "node", pid: 2_311),
        PortmanRemotePort(port: forwardPort, processName: "postgres", pid: 977),
        PortmanRemotePort(port: 6379, processName: "redis-server", pid: 1_018),
        PortmanRemotePort(port: 9090, processName: "prometheus", pid: 1_466),
    ]

    /// Forward page stills: `portman-hosts` opens the Hosts select, `portman-menu` right-clicks a host card,
    /// `portman-scan` opens that card's Scan ports sheet. Clicks go to the panel window in-process; the pointer never moves.
    static func forwardScene(_ action: @escaping @MainActor () -> Void) -> DemoScene {
        DemoScene(
            open: {
                seed()
                PortmanMenuController.shared.demoAnchor = menuBarAnchor()
                PortmanMenuController.shared.show(initialPage: .forward, activateApp: false)
            },
            steps: [DemoStep(at: 0.5, run: action)]
        )
    }

    static var hostsScene: DemoScene { forwardScene { DemoClick.element(labeled: "Choose an SSH host") } }
    static var modeScene: DemoScene { forwardScene { DemoClick.element(labeled: "What to do with this host") } }
    static var menuScene: DemoScene { forwardScene { DemoClick.element(labeled: "\(forwardHost), 1 forward", right: true) } }
    static var scanScene: DemoScene {
        forwardScene { NotificationCenter.default.post(name: scanPortsNotification, object: forwardHost) }
    }

    /// Stand-in ~/.ssh/config hosts, so stills never show the real file.
    static let sshHostNames = [forwardHost: "10.0.4.12", "gpu-lab": "gpu-lab.internal", offlineHost: "203.0.113.40"]
    /// The scan of this host fails, for the Add a server error still.
    static let offlineHost = "staging-eu"
    static let offlineMessage = "ssh: connect to host 203.0.113.40 port 22: Operation timed out"

    /// `portman-forward`: the job switch over the host cards. `portman-empty`: no servers yet.
    /// `portman-add`: Add a server step 2 with two ports ticked. `portman-add-error`: step 2 when the host does not answer.
    static var jobSwitchScene: DemoScene { forwardScene {} }
    static var emptyScene: DemoScene { emptyForwardScene([]) }
    static var addScene: DemoScene {
        emptyForwardScene([
            DemoStep(at: 0.3) { DemoClick.element(labeled: "Add a server") },
            DemoStep(at: 0.7) { DemoClick.element(labeled: forwardHost) },
            DemoStep(at: 1.1) { DemoClick.element(labeled: "Select remote port 3000") },
            DemoStep(at: 1.3) { DemoClick.element(labeled: "Select remote port \(String(forwardPort))") },
            DemoStep(at: 1.5) { DemoClick.element(labeled: "Both") },
        ])
    }
    static var pickScene: DemoScene {
        emptyForwardScene([DemoStep(at: 0.3) { DemoClick.element(labeled: "Add a server") }])
    }
    static var addErrorScene: DemoScene {
        emptyForwardScene([
            DemoStep(at: 0.3) { DemoClick.element(labeled: "Add a server") },
            DemoStep(at: 0.7) { DemoClick.element(labeled: offlineHost) },
        ])
    }

    private static func emptyForwardScene(_ steps: [DemoStep]) -> DemoScene {
        DemoScene(
            open: {
                seed(webMB: webPeakMB, webCPU: webPeakCPU, hosts: false)
                PortmanMenuController.shared.demoAnchor = menuBarAnchor()
                PortmanMenuController.shared.show(initialPage: .forward, activateApp: false)
            },
            steps: steps
        )
    }

    static var scene: DemoScene {
        DemoScene(
            open: {
                seed(webMB: webStartMB, webCPU: webStartCPU)
                PortmanMenuController.shared.demoAnchor = menuBarAnchor()
                ToolActionRouter.shared.open(toolID: "portman", activateApp: false)
            },
            steps: climb + [DemoStep(at: stopAt) { stopWeb() }]
        )
    }

    /// `portman-detail`: the Vite row's Details page with its Tool and Started by rows.
    static var detailScene: DemoScene {
        DemoScene(
            open: {
                seed()
                PortmanMenuController.shared.demoAnchor = menuBarAnchor()
                ToolActionRouter.shared.open(toolID: "portman", activateApp: false)
            },
            steps: [DemoStep(at: 0.8) { DemoClick.press(labeled: "Show port 5173 details") },
                    DemoStep(at: 1.8) { DemoClick.element(labeled: "Details") }]
        )
    }

    private static var climb: [DemoStep] {
        (1...climbSteps).map { step in
            let progress = Double(step) / Double(climbSteps)
            let eased = 1 - (1 - progress) * (1 - progress)
            return DemoStep(at: climbStart + climbDuration * progress) {
                PortmanService.shared.demoSetUsage(
                    port: webPort,
                    memoryBytes: bytes(webStartMB + (webPeakMB - webStartMB) * eased),
                    cpuPercent: webStartCPU + (webPeakCPU - webStartCPU) * eased
                )
            }
        }
    }

    /// A clear status-item-sized view at the top right of the main screen, standing in for Portman's menu bar icon.
    private static func menuBarAnchor() -> NSView {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = NSSize(width: 24, height: 24)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: visible.maxX - 200, y: visible.maxY), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window.contentView!
    }

    /// Goes through the real Stop entry point; its demo guard only drops the row from memory.
    private static func stopWeb() {
        guard let web = PortmanService.shared.localPorts.first(where: { $0.port == webPort }) else { return }
        PortmanService.shared.stopLocal(web)
    }

    private static func seed(webMB: Double, webCPU: Double, hosts: Bool = true) {
        let now = Date()
        let ports = servers.map { server in
            let isWeb = server.port == webPort
            let title = server.title ?? server.argv.joined(separator: " ")
            var port = PortmanLocalPort(
                pid: server.pid, port: server.port, address: "127.0.0.1",
                command: server.executable.isEmpty ? server.argv[0] : URL(fileURLWithPath: server.executable).lastPathComponent,
                launchCommand: title,
                memoryBytes: bytes(isWeb ? webMB : server.memoryMB),
                cpuPercent: isWeb ? webCPU : server.cpuPercent, uptime: server.uptime,
                started: UInt64((now.timeIntervalSince1970 - server.upSeconds) * 1_000_000),
                userID: geteuid(), hasConnections: true
            )
            port.executablePath = server.executable
            port.appBundlePath = server.app
            port.origin = PortmanOrigin.resolve(
                PortmanCommandContext(argv: server.argv, title: title, executablePath: server.executable),
                catalog: .bundled, ancestor: server.app, environment: server.environment,
                startedByApp: server.startedByApp.map { ($0, URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) }
            )
            return port
        }
        let metadata = Dictionary(uniqueKeysWithValues: zip(ports, servers).compactMap { port, server in
            server.project.map { project in
                let folder = "/Users/demo/dev/\(project)"
                return (port.id, PortmanMetadata(folder: folder, project: project, branch: server.branch, root: folder))
            }
        })
        let history = Dictionary(uniqueKeysWithValues: ports.map { ($0.id, samples(for: $0, now: now)) })
        PortmanService.shared.demoSeed(
            ports: ports, metadata: metadata, history: history,
            tunnels: hosts ? [PortmanTunnel(id: UUID(), host: forwardHost, remotePort: forwardPort,
                                              localPort: forwardPort, state: .running)] : []
        )
        PortmanHostList.shared.demoSeed(hosts ?
            [PortmanHost(destination: forwardHost, mode: .forward,
                         forwards: [PortmanForwardSpec(remotePort: forwardPort, localPort: forwardPort)])]
                + otherHosts.map { PortmanHost(destination: $0, mode: .forward) } : []
        )
    }

    private static func samples(for port: PortmanLocalPort, now: Date) -> [PortmanSample] {
        let count = port.port == webPort ? 2 : historySamples
        return (0..<count).map { index in
            let wobble = 1 + historyWobble * sin(Double(index + Int(port.port)))
            return PortmanSample(
                date: now.addingTimeInterval(-historySpacing * Double(count - 1 - index)),
                memoryBytes: Int64(Double(port.memoryBytes) * wobble),
                cpuPercent: port.cpuPercent * wobble
            )
        }
    }

    private static func bytes(_ megabytes: Double) -> Int64 { Int64(megabytes * bytesPerMB) }
}
#endif

import AppKit

// Records the event and ordering context of unexpected activation.
@MainActor
enum ActivationDiagnostics {
    nonisolated private static let maximumBytes = 256 * 1024
    private static var lastURL = ""
    private static var lastURLTime = Date.distantPast
    private static var routeWasActive = false
    private static var routeFrontmost = "unobserved"
    private static var beforeActivation = "unobserved"
    private static var lastExternalFrontmost = "unobserved"
    private static var orderings: [(time: TimeInterval, method: String, window: String, active: Bool, frontmost: String)] = []
    private static var observers: [NSObjectProtocol] = []
    nonisolated private static let writer = DispatchQueue(label: "MacPowerToys.activation-diagnostics", qos: .utility)

    private static var fileURL: URL {
        AppDataLocation.directory
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("activations.log")
    }

    static func install() {
        guard observers.isEmpty else { return }
        noteFrontmost()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    lastExternalFrontmost = identity(app)
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                beforeActivation = identity(NSWorkspace.shared.frontmostApplication)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { record() }
        })
    }

    static func noteURL(_ url: URL) {
        lastURL = url.absoluteString
        lastURLTime = Date()
        routeWasActive = NSApp.isActive
        routeFrontmost = noteFrontmost()
        beforeActivation = "unobserved"
    }

    static func noteOrdering(_ method: String, window: NSWindow) {
        let now = ProcessInfo.processInfo.systemUptime
        orderings.removeAll { now - $0.time > 3 }
        orderings.append((now, method, window.identifier?.rawValue ?? "#\(window.windowNumber)",
                          NSApp.isActive, noteFrontmost()))
    }

    private static func identity(_ app: NSRunningApplication?) -> String {
        app.map { "\($0.bundleIdentifier ?? "unknown"):\($0.processIdentifier)" } ?? "none"
    }

    @discardableResult
    private static func noteFrontmost() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let value = identity(app)
        if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalFrontmost = value
        }
        return value
    }

    private static func record() {
        let event = NSApp.currentEvent
        let eventText = event.map {
            "type=\($0.type.rawValue) subtype=\($0.subtype.rawValue) window=\($0.window?.identifier?.rawValue ?? "-")"
        } ?? "none"
        let key = NSApp.keyWindow?.identifier?.rawValue ?? "-"
        let sinceURL = String(format: "%.2f", Date().timeIntervalSince(lastURLTime))
        let now = ProcessInfo.processInfo.systemUptime
        orderings.removeAll { now - $0.time > 3 }
        let orderingText = orderings.map {
            "\($0.method)[window=\($0.window) age=\(String(format: "%.3f", now - $0.time))s active=\($0.active) front=\($0.frontmost)]"
        }.joined(separator: "; ")
        let stack = Thread.callStackSymbols.prefix(14).joined(separator: "\n")
        let line = """
        \(Date().timeIntervalSince1970) event[\(eventText)] key=\(key) lastURL=\(lastURL) sinceURL=\(sinceURL)s
        routeActive=\(routeWasActive) routeFront=\(routeFrontmost) willActivateFront=\(beforeActivation) lastExternalFront=\(lastExternalFrontmost) active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)
        orders3s=\(orderings.count) \(orderingText)
        stack:\n\(stack)

        """
        let url = fileURL
        writer.async { write(line, to: url) }
    }

    nonisolated private static func write(_ line: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

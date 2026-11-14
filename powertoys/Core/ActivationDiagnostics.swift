import AppKit

// Records the event and ordering context of unexpected activation.
@MainActor
enum ActivationDiagnostics {
    nonisolated private static let maximumBytes = 256 * 1024
    nonisolated private static let maximumAge: TimeInterval = 14 * 24 * 60 * 60
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
        lastURL = redacted(url)
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
        // Raw return addresses are cheap; symbol lookup runs on the writer queue.
        let addresses = Thread.callStackReturnAddresses.prefix(14).map(\.uintValue)
        let header = """
        \(Date().timeIntervalSince1970) event[\(eventText)] key=\(key) lastURL=\(lastURL) sinceURL=\(sinceURL)s
        routeActive=\(routeWasActive) routeFront=\(routeFrontmost) willActivateFront=\(beforeActivation) lastExternalFront=\(lastExternalFrontmost) active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)
        orders3s=\(orderings.count) \(orderingText)
        """
        let url = fileURL
        writer.async {
            write(header + "\nstack:\n" + symbolicate(addresses) + "\n\n", to: url)
        }
    }

    // Query, fragment, and credentials can carry tokens; the route path is enough to diagnose.
    nonisolated static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "-" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "-"
    }

    nonisolated private static func symbolicate(_ addresses: [UInt]) -> String {
        addresses.enumerated().map { index, address in
            var info = Dl_info()
            guard let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0 else {
                return "\(index) 0x\(String(address, radix: 16))"
            }
            let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
            let symbol = info.dli_sname.map { String(cString: $0) } ?? "?"
            let offset = info.dli_saddr.map { address &- UInt(bitPattern: $0) } ?? 0
            return "\(index) \(image) \(symbol) + \(offset)"
        }.joined(separator: "\n")
    }

    // Entries end with a blank line and start with their Unix time; drop expired, then oldest, entries.
    nonisolated static func bounded(_ log: String, now: TimeInterval, maximumBytes: Int, maximumAge: TimeInterval) -> String {
        var entries = log.components(separatedBy: "\n\n").filter { entry in
            guard let stamp = entry.split(separator: " ", maxSplits: 1).first.flatMap({ Double($0) }) else { return false }
            return now - stamp <= maximumAge
        }
        var size = entries.reduce(0) { $0 + $1.utf8.count + 2 }
        while size > maximumBytes, !entries.isEmpty {
            size -= entries.removeFirst().utf8.count + 2
        }
        return entries.map { $0 + "\n\n" }.joined()
    }

    nonisolated private static func write(_ entry: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let log = bounded(existing + entry, now: Date().timeIntervalSince1970,
                              maximumBytes: maximumBytes, maximumAge: maximumAge)
            try Data(log.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("ActivationDiagnostics write failed: %@", error.localizedDescription)
        }
    }
}

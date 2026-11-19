import AppKit
import Darwin

/// The installed Task Manager a top-process row can open: Pro first, then Classic.
nonisolated enum MainPanelTaskManager: String, CaseIterable {
    // shortcut: Pro has no Xcode project yet, so its bundle id follows Classic's pattern; confirm it when Pro builds.
    // shortcut: an installed Pro counts as paid; add the license check once Pro has licensing.
    case pro = "com.surajmandal.taskmanager.pro"
    case classic = "com.surajmandal.taskmanager.classic"

    var menuTitle: String { self == .pro ? "Open in Task Manager Pro" : "Open in Task Manager Classic" }

    static func installed() -> Self? {
        allCases.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil }
    }

    /// Neither app takes a PID argument or URL yet, so this opens the app only.
    func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

/// Quit Process from the panel: an Activity Monitor style confirmation, then Quit or Force Quit.
@MainActor
enum MainPanelProcessQuit {
    nonisolated enum Failure: Equatable, Sendable {
        case exited, notPermitted, other(Int32)
    }

    /// Asks first; nothing is sent without Quit or Force Quit. The panel closes so it never covers the alert.
    /// The alert runs without activating the app; its buttons take clicks at once.
    static func confirm(name: String, pid: pid_t, started: UInt64) {
        MainMenuBarController.shared.closePanel()
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Are you sure you want to quit \(name)?"
            alert.informativeText = "Force Quit stops it at once. Unsaved changes are lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Force Quit").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            let force: Bool
            switch alert.runModal() {
            case .alertFirstButtonReturn: force = false
            case .alertSecondButtonReturn: force = true
            default: return
            }
            guard let failure = send(force: force, pid: pid, started: started) else { return }
            let error = NSAlert()
            error.alertStyle = .warning
            error.messageText = "\(name) could not be quit"
            error.informativeText = switch failure {
            case .exited: "It has already quit."
            case .notPermitted: "It runs as another user or as the system, so MacPowerToys is not allowed to quit it."
            case .other(let code): String(cString: strerror(code))
            }
            error.runModal()
        }
    }

    /// Apps get the AppKit quit; other processes get SIGTERM, or SIGKILL when forced.
    static func send(force: Bool, pid: pid_t, started: UInt64) -> Failure? {
        guard isSameProcess(pid: pid, started: started) else { return .exited }
        if let app = NSRunningApplication(processIdentifier: pid) {
            if force ? app.forceTerminate() : app.terminate() { return nil }
            return app.isTerminated ? .exited : signal(force ? SIGKILL : SIGTERM, pid: pid)
        }
        return signal(force ? SIGKILL : SIGTERM, pid: pid)
    }

    /// `kill` with its errno mapped to what the alert says. Signal 0 only checks permission.
    nonisolated static func signal(_ signal: Int32, pid: pid_t) -> Failure? {
        guard pid > 0 else { return .exited }
        if kill(pid, signal) == 0 { return nil }
        switch errno {
        case ESRCH: return .exited
        case EPERM: return .notPermitted
        case let code: return .other(code)
        }
    }

    /// The PID still names the sampled process, not a new one that reused it. A protected row has no start time.
    nonisolated static func isSameProcess(pid: pid_t, started: UInt64) -> Bool {
        guard started != 0 else { return true }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec == started
    }
}

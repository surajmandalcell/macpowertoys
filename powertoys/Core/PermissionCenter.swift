import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Observation
import OnePlusUI
import SwiftUI
import UserNotifications

nonisolated enum PermissionKind: CaseIterable, Sendable {
    case accessibility, screenRecording, microphone, notifications
}

extension Notification.Name {
    static let permissionsChanged = Notification.Name("com.surajmandal.macpowertoys.permissionsChanged")
}

/// The one place that reads macOS permission state. Reads never prompt; prompts come only from `request`.
@Observable
@MainActor
final class PermissionCenter {
    typealias Reader = @Sendable () async -> Set<PermissionKind>

    static let shared = PermissionCenter(read: nil)

    private(set) var granted: Set<PermissionKind>
    /// Kept as the full status so a view can tell "never asked" from "denied".
    private(set) var microphoneStatus = AVAuthorizationStatus.notDetermined
    @ObservationIgnored private let read: Reader
    @ObservationIgnored private let readsFanHelper: Bool
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var watchers: [UUID: PermissionKind] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var isPolling: Bool { pollTask != nil }

    init(read: Reader?, pollInterval: Duration = .seconds(2)) {
        let observesSystem = read == nil && !AppRuntime.isRunningTests
        self.read = read ?? { await PermissionCenter.readGranted() }
        readsFanHelper = observesSystem
        self.pollInterval = pollInterval
        granted = observesSystem ? Self.readGrantedWithoutWaiting() : []
        guard observesSystem else { return }
        refreshMicrophone()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in await PermissionCenter.shared.refresh() }
        }
        // macOS posts this when the Accessibility list changes, so a later grant needs no activation.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.accessibility.api"),
                                                            object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                await PermissionCenter.shared.refresh()
            }
        }
        Task { await refresh() }
    }

    func isGranted(_ kind: PermissionKind) -> Bool { granted.contains(kind) }

    func isMissing(_ kind: PermissionKind) -> Bool { !granted.contains(kind) }

    func refresh() async {
        let next = await read()
        if readsFanHelper { refreshMicrophone() }
        let daemonBefore = readsFanHelper ? FanHelperService.shared.status : nil
        if readsFanHelper { await FanHelperService.shared.refresh() }
        let changed = next != granted || (readsFanHelper && daemonBefore != FanHelperService.shared.status)
        if next != granted { granted = next }
        updatePolling()
        if changed { NotificationCenter.default.post(name: .permissionsChanged, object: self) }
    }

    /// What a missing Accessibility approval means. macOS keeps an approval per code signature, so after a signing
    /// change the switch in Settings stays on while `AXIsProcessTrusted` is false.
    var accessibilityProblem: String? {
        // The demo stands in for a set-up Mac, where Accessibility is granted.
        guard !DemoMode.isActive, isMissing(.accessibility) else { return nil }
        return UserDefaults.standard.bool(forKey: Self.accessibilityWasGrantedKey)
            ? "macOS has an old approval for MacPowerToys. Turn it off and on again in Accessibility, or click Fix."
            : "MacPowerToys needs Accessibility to change scrolling. Click Fix, then switch MacPowerToys on."
    }

    /// Fix: drops this app's Accessibility rows (stale signatures included), asks again so macOS lists the current
    /// build, and opens the Accessibility pane. Call only from a click.
    func fixAccessibility() {
        Task {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.surajmandal.macpowertoys"
            _ = try? await Task.detached { try FanCommand.run("/usr/bin/tccutil", ["reset", "Accessibility", bundleID]) }.value
            requestAccessibility()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    nonisolated static let requestScreenCaptureArgument = "--request-screen-capture"

    /// Fix: drops this app's Screen Recording rows (a 1.x Apple Development signature keeps the switch on but
    /// denies the Developer ID build), then reopens the app, which asks again at launch so macOS writes a row for
    /// this signature. CoreGraphics caches the answer per process: a request in this process never reaches macOS.
    /// Call only from a click.
    func fixScreenRecording() {
        Task {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.surajmandal.macpowertoys"
            _ = try? await Task.detached { try FanCommand.run("/usr/bin/tccutil", ["reset", "ScreenCapture", bundleID]) }.value
            relaunch(arguments: ["--open", "text-extractor", Self.requestScreenCaptureArgument])
        }
    }

    /// Runs at launch after Fix. macOS shows its prompt and lists this signature in Screen & System Audio Recording.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        Task { await refresh() }
    }

    /// Starts a new copy once this one has quit (the instance lock lets only one run), then quits.
    /// Quit can take over a minute (fan, Color Picker, RSync, and log steps), so the new copy waits up to 120 s.
    private func relaunch(arguments: [String]) {
        if DemoMode.blocks("app.relaunch") { return }
        let script = """
        pid=$1; app=$2; shift 2; i=0
        while /bin/kill -0 "$pid" 2>/dev/null; do i=$((i+1)); [ $i -gt 600 ] && exit 1; sleep 0.2; done
        exec /usr/bin/open -a "$app" --args "$@"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "relaunch", String(getpid()), Bundle.main.bundlePath] + arguments
        do { try process.run() } catch { return }
        // Not from this Task: terminate's wait loop would block the main actor, and the quit steps need it.
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    nonisolated static let accessibilityWasGrantedKey = "permissions.accessibilityWasGranted"

    /// Call only from an explicit user action or when the user turns on a tool that needs `kind`.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Task { await refresh() }
    }

    /// Prompt-free; updates the microphone status at once.
    func refreshMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphoneStatus != status { microphoneStatus = status }
    }

    /// Call only from an explicit user action. macOS shows the prompt only while undetermined.
    func requestMicrophone() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        refreshMicrophone()
        await refresh()
    }

    /// A visible row that shows `kind` registers here; nil unregisters it.
    func watch(_ id: UUID, kind: PermissionKind?) {
        watchers[id] = kind
        updatePolling()
    }

    private func updatePolling() {
        let needed = watchers.values.contains(where: isMissing)
        if needed, pollTask == nil {
            let interval = pollInterval
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        } else if !needed, let pollTask {
            pollTask.cancel()
            self.pollTask = nil
        }
    }

    /// Asks once, when the first notification would be sent. macOS shows the prompt only while undetermined.
    nonisolated static func allowNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
            await PermissionCenter.shared.refresh()
        }
        return status == .authorized || status == .provisional
    }

    nonisolated private static func readGrantedWithoutWaiting() -> Set<PermissionKind> {
        var granted = Set<PermissionKind>()
        if AXIsProcessTrusted() {
            granted.insert(.accessibility)
            if !AppRuntime.isRunningTests { UserDefaults.standard.set(true, forKey: accessibilityWasGrantedKey) }
        }
        if CGPreflightScreenCaptureAccess() { granted.insert(.screenRecording) }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { granted.insert(.microphone) }
        return granted
    }

    nonisolated private static func readGranted() async -> Set<PermissionKind> {
        var granted = readGrantedWithoutWaiting()
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional { granted.insert(.notifications) }
        return granted
    }
}

extension View {
    /// Re-reads `kind` every 2 s while this view is on screen and the permission is missing.
    func permissionWatch(_ kind: PermissionKind) -> some View {
        background(PermissionWatcher(kind: kind).onePlusLiveUpdates())
    }
}

private struct PermissionWatcher: View {
    let kind: PermissionKind
    @Environment(\.onePlusIsVisible) private var isVisible
    @State private var id = UUID()

    var body: some View {
        Color.clear
            .onChange(of: isVisible, initial: true) { _, visible in
                PermissionCenter.shared.watch(id, kind: visible ? kind : nil)
            }
            .onDisappear { PermissionCenter.shared.watch(id, kind: nil) }
    }
}

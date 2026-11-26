import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Observation
import OnePlusUI
import SamPermissions
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
        Self.connectSamPermissions()
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

    /// Fix buttons. SamPermissions picks the step: guide, ask, reset an old-signature row, or reopen. Click only.
    func fixAccessibility() { SamPermissions.shared.resolve(.accessibility) }

    func fixScreenRecording() { SamPermissions.shared.resolve(.screenRecording) }

    private static func connectSamPermissions() {
        let permissions = SamPermissions.shared
        permissions.reopenArguments = { $0 == .screenRecording ? ["--open", "text-extractor"] : [] }
        permissions.canReopen = { !DemoMode.blocks("app.relaunch") }
        permissions.onChange = { _ in Task { await PermissionCenter.shared.refresh() } }
        permissions.onLoop = { _, report in
            let alert = NSAlert()
            alert.messageText = "Permission fix is not working"
            alert.informativeText = "macOS keeps refusing the permission. Send a short report? It holds the macOS and app version only."
            alert.addButton(withTitle: "Send Report")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn { DailyCounts.sendReport(report) }
        }
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

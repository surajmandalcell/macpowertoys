import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Observation
import OnePlusUI
import ServiceManagement
import SwiftUI
import UserNotifications

nonisolated enum PermissionKind: CaseIterable, Sendable {
    case accessibility, screenRecording, microphone, notifications, backgroundDaemon
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

    func isGranted(_ kind: PermissionKind) -> Bool {
        kind == .backgroundDaemon ? FanHelperService.shared.isEnabled : granted.contains(kind)
    }

    /// A daemon that was never enabled is not missing; only one that waits for Login Items approval is.
    func isMissing(_ kind: PermissionKind) -> Bool {
        kind == .backgroundDaemon ? FanHelperService.shared.status == .requiresApproval : !granted.contains(kind)
    }

    func refresh() async {
        let next = await read()
        let daemonBefore = readsFanHelper ? FanHelperService.shared.status : nil
        if readsFanHelper { await FanHelperService.shared.refresh() }
        let changed = next != granted || (readsFanHelper && daemonBefore != FanHelperService.shared.status)
        if next != granted { granted = next }
        updatePolling()
        if changed { NotificationCenter.default.post(name: .permissionsChanged, object: self) }
    }

    /// Call only from an explicit user action or when the user turns on a tool that needs `kind`.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Task { await refresh() }
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
        if AXIsProcessTrusted() { granted.insert(.accessibility) }
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

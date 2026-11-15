import AppKit
import OnePlusUI
import SwiftUI

struct RcloneSidebarView: View {
    @Environment(RcloneJobManager.self) private var manager
    @Binding var content: RSyncContent
    @Binding var showAddRemote: Bool

    private var devSyncManager: DevSyncManager { .shared }

    var body: some View {
        OnePlusLinearSidebar {
            EmptyView()
        } navigation: {
            OnePlusLinearNavCaption("Transfers")
            ForEach(JobFilter.allCases) { filter in
                let index = JobFilter.allCases.firstIndex(of: filter) ?? 0
                OnePlusLinearNavRow(
                    filter.displayName,
                    systemImage: filter.icon,
                    selected: content == .transfers && manager.filter == filter,
                    count: manager.count(for: filter)
                ) {
                    manager.filter = filter
                    content = .transfers
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                .accessibilityIdentifier("rclone.transfers.\(filter.rawValue)")
            }

            OnePlusLinearNavRow("Activity", systemImage: "clock.arrow.circlepath", selected: content == .activity) {
                content = .activity
            }
            .keyboardShortcut("5")
            OnePlusLinearNavRow(
                "Dev Sync",
                systemImage: "externaldrive.badge.plus",
                selected: content == .devSync,
                count: DevSyncSidebarBadge.count(devSyncManager.attentionCount)
            ) {
                content = .devSync
            }
            .keyboardShortcut("6")

            remotesHeader
            if manager.remotes.isEmpty {
                LinearCaption("No remotes configured")
                    .padding(.horizontal, OnePlusLinearMetrics.navPadding)
                    .frame(height: OnePlusLinearMetrics.navRow)
            } else {
                ForEach(manager.remotes) { remote in
                    let index = manager.remotes.firstIndex(of: remote) ?? manager.remotes.count
                    RcloneRemoteNavRow(
                        remote: remote,
                        selected: content == .browse(remote),
                        showAddRemote: $showAddRemote
                    ) {
                        content = .browse(remote)
                    }
                    .modifier(RemoteShortcut(index: index))
                }
            }
        } bottom: {
            if !manager.daemonIsHealthy {
                OnePlusLinearNavRow("Reconnect", systemImage: "arrow.clockwise") {
                    Task { await manager.restartDaemon() }
                }
            }
            OnePlusLinearNavRow("Settings", systemImage: "gearshape", selected: content == .settings, shortcut: "⌘,") {
                content = .settings
            }
            .keyboardShortcut(",")
        }
    }

    private var remotesHeader: some View {
        OnePlusLinearNavCaption("Remotes")
            .overlay(alignment: .bottomTrailing) {
                OnePlusLinearIconButton(systemImage: "plus", help: "Add remote", size: OnePlusLinearMetrics.toolbarButton) {
                    showAddRemote = true
                }
            }
    }

}

private struct RemoteShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 3 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index + 7))))
        } else {
            content
        }
    }
}

private struct RcloneRemoteNavRow: View {
    @Environment(RcloneJobManager.self) private var manager
    let remote: RcloneRemote
    let selected: Bool
    @Binding var showAddRemote: Bool
    let action: () -> Void
    @State private var showSettings = false
    @State private var showCleanup = false
    @State private var confirmRemoval = false

    var body: some View {
        OnePlusLinearNavRow(
            remote.displayName,
            systemImage: remote.icon,
            selected: selected,
            shortcut: remote.typeLabel,
            action: action
        )
        .accessibilityValue(remote.typeLabel)
        .contextMenu {
            Button("Remote Settings…") { showSettings = true }
            Button("Reconnect…") {
                manager.beginReconnect(remote)
                showAddRemote = true
            }
            Button("Clean Up by Ignore Rules…") { showCleanup = true }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(remote.name, forType: .string)
            }
            Divider()
            Button("Remove…", role: .destructive) { confirmRemoval = true }
        }
        .sheet(isPresented: $showSettings) { RemoteSettingsSheet(remote: remote) }
        .sheet(isPresented: $showCleanup) { CleanupRemoteSheet(remote: remote, startPath: "") }
        .confirmationDialog("Remove \"\(remote.displayName)\"?", isPresented: $confirmRemoval) {
            Button("Remove remote", role: .destructive) { manager.removeRemote(remote) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the remote from rclone. It does not delete files.")
        }
        .accessibilityIdentifier("rclone.remote.\(remote.name)")
    }
}

#Preview {
    RcloneSidebarView(content: .constant(.transfers), showAddRemote: .constant(false))
        .environment(RcloneJobManager())
        .frame(height: OnePlusWindowCanvas.rclone.size.height)
}

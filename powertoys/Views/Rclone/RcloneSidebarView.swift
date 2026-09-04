//
//  RcloneSidebarView.swift
//  powertoys
//

import SwiftUI

struct RcloneSidebarView: View {
    @Environment(RcloneJobManager.self) private var manager
    @Binding var content: RSyncContent
    @Binding var showAddRemote: Bool

    private var devSyncManager: DevSyncManager { .shared }

    var body: some View {
        ZStack(alignment: .topLeading) {
            sidebarBody
            titleRow
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text("Cloud Sync")
                .font(.system(size: 13, weight: .medium))

            Circle()
                .fill(daemonStatusColor)
                .frame(width: 6, height: 6)

            if case .running(_, let version) = manager.daemon.state {
                Text(version)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !manager.daemonIsHealthy {
                Button {
                    Task { await manager.restartDaemon() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Reconnect")
            }
        }
        .padding(.leading, UtilityLayout.workspaceTitleLeadingInset)
        .padding(.top, 8)
    }

    private var daemonStatusColor: Color {
        switch manager.daemon.state {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var sidebarBody: some View {
        VStack(spacing: 0) {
            NewTransferButton {
                manager.isPresentingNewTransfer = true
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)


            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: "Show")

                    ForEach(JobFilter.allCases) { filter in
                        FilterRow(
                            filter: filter,
                            count: manager.count(for: filter),
                            isSelected: content == .transfers && manager.filter == filter
                        ) {
                            content = .transfers
                            manager.filter = filter
                        }
                    }

                    NavRow(
                        icon: "clock.arrow.circlepath",
                        title: "Activity",
                        isSelected: content == .activity
                    ) {
                        content = .activity
                    }
                    .padding(.top, 8)

                    NavRow(
                        icon: "externaldrive.badge.plus",
                        title: "Dev Sync",
                        count: devSyncManager.attentionCount,
                        isSelected: content == .devSync
                    ) {
                        content = .devSync
                    }
                    .padding(.top, 8)

                    RemotesSectionHeader {
                        showAddRemote = true
                    }

                    if manager.remotes.isEmpty {
                        Text("No remotes configured")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(manager.remotes) { remote in
                            RemoteRow(
                                remote: remote,
                                isSelected: content == .browse(remote),
                                onReconnect: {
                                    manager.beginReconnect(remote)
                                    showAddRemote = true
                                }
                            ) {
                                content = .browse(remote)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .thinScrollIndicators()

            NavRow(
                icon: "gearshape",
                title: "Settings",
                isSelected: content == .settings
            ) {
                content = .settings
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
    }
}

// MARK: - New Transfer Button

private struct NewTransferButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("New Transfer")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(isHovering ? 0.85 : 1.0))
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Filter Row

private struct FilterRow: View {
    let filter: JobFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 18)

                Text(filter.displayName)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return .accentColor }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

// MARK: - Nav Row

private struct NavRow: View {
    let icon: String
    let title: String
    var count: Int = 0
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.75))

                Spacer()

                if let badge = DevSyncSidebarBadge.text(count) {
                    Text(badge)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return .accentColor }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

// MARK: - Remotes Section Header

private struct RemotesSectionHeader: View {
    let addAction: () -> Void

    @State private var isHoveringAdd = false

    var body: some View {
        HStack {
            Text("REMOTES")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: addAction) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHoveringAdd ? Color.primary.opacity(0.06) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { isHoveringAdd = $0 }
        .help("Add cloud connector")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - Remote Row

private struct RemoteRow: View {
    @Environment(RcloneJobManager.self) private var manager
    let remote: RcloneRemote
    let isSelected: Bool
    let onReconnect: () -> Void
    let action: () -> Void

    @State private var isHovering = false
    @State private var isConfirmingRemoval = false
    @State private var isShowingSettings = false
    @State private var isShowingCleanup = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: remote.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 18)

                Text(remote.displayName)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(remote.typeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Remote Settings…") {
                isShowingSettings = true
            }
            Button("Reconnect…") {
                onReconnect()
            }
            Button("Clean Up by Ignore Rules…") {
                isShowingCleanup = true
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(remote.name, forType: .string)
            }
            Divider()
            Button("Remove…", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            RemoteSettingsSheet(remote: remote)
        }
        .sheet(isPresented: $isShowingCleanup) {
            CleanupRemoteSheet(remote: remote, startPath: "")
        }
        .confirmationDialog(
            "Remove \"\(remote.displayName)\"?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Remove remote", role: .destructive) {
                manager.removeRemote(remote)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove deletes this remote from the rclone configuration. It does not delete files.")
        }
    }

    private var background: Color {
        if isSelected { return .accentColor }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

#Preview {
    RcloneSidebarView(content: .constant(.transfers), showAddRemote: .constant(false))
        .environment(RcloneJobManager())
        .frame(width: 264, height: 640)
}

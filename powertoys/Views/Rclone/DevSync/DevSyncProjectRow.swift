//
//  DevSyncProjectRow.swift
//  powertoys
//

import SwiftUI

struct DevSyncProjectRow: View {
    let pair: DevSyncPair
    let project: DevProject
    let manager: DevSyncManager

    @State private var isHovering = false
    @State private var isShowingDrift = false

    private var driftPaths: [String] { manager.driftPaths[project.id] ?? [] }

    private var linkNeedsRepair: Bool {
        guard let link = manager.link(for: project) else { return false }
        return link.state != .healthy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityLine
            metricsLine

            ForEach(project.warnings, id: \.self) { warning in
                Label(warning.displayName, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if project.state == .missing {
                missingDecisions
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        )
        .utilityAnimation(value: isHovering)
        .utilityAnimation(value: project.state)
        .onHover { isHovering = $0 }
    }

    // MARK: Identity

    private var identityLine: some View {
        HStack(spacing: 10) {
            residencyChip
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13))
                Text(project.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            DevSyncStateBadge(
                icon: project.residency.icon,
                title: project.residency.displayName,
                tint: .secondary
            )
            DevSyncStateBadge(
                icon: stateIcon,
                title: project.state.displayName,
                tint: project.state.tint
            )
        }
    }

    private var residencyChip: some View {
        Image(systemName: project.residency.icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
            .accessibilityHidden(true)
    }

    private var stateIcon: String {
        switch project.state {
        case .clean: return "checkmark.circle.fill"
        case .syncing: return "arrow.up.arrow.down.circle"
        case .conflict: return "exclamationmark.triangle.fill"
        case .destinationDrift: return "arrow.triangle.branch"
        case .linkOffline, .linkMissing: return "link.badge.plus"
        case .missing: return "questionmark.circle"
        case .paused: return "pause.circle.fill"
        case .error, .blockedByTopology, .blockedByFileSystem: return "hand.raised.fill"
        default: return "clock"
        }
    }

    // MARK: Metrics

    private var metricsLine: some View {
        HStack(spacing: 8) {
            Text(metricsText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if !driftPaths.isEmpty {
                driftButton
            }

            Spacer(minLength: 8)

            DevSyncIconButton(icon: "arrow.triangle.2.circlepath", label: "Sync Project") {
                Task { await manager.syncProject(pairID: pair.id, projectID: project.id) }
            }
            DevSyncIconButton(icon: "list.bullet.clipboard", label: "Preview") {
                Task { await manager.previewProject(pairID: pair.id, projectID: project.id) }
            }
            projectMenu
        }
    }

    private var metricsText: String {
        [
            "included \(RcloneFormat.bytes(project.includedBytes))",
            "excluded \(RcloneFormat.bytes(project.excludedBytes))",
            "synced \(DevSyncFormat.relative(project.lastSuccessAt, fallback: "never"))"
        ].joined(separator: " · ")
    }

    private var driftButton: some View {
        Button {
            isShowingDrift = true
        } label: {
            DevSyncStateBadge(
                icon: "arrow.triangle.branch",
                title: DevSyncFormat.count(driftPaths.count, singular: "drift path", plural: "drift paths"),
                tint: .orange
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .help("Resolve destination drift")
        .accessibilityLabel("Resolve destination drift")
        .popover(isPresented: $isShowingDrift, arrowEdge: .bottom) {
            driftPopover
        }
    }

    private var driftPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            DevSyncSectionHeader(title: "Drift paths")
            ForEach(driftPaths, id: \.self) { path in
                VStack(alignment: .leading, spacing: 4) {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        ForEach(DevDriftResolution.allCases, id: \.self) { resolution in
                            Button(resolution.displayName) {
                                Task {
                                    await manager.resolveDrift(
                                        pairID: pair.id,
                                        projectID: project.id,
                                        relativePath: path,
                                        resolution: resolution
                                    )
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
    }

    // MARK: Menu

    private var projectMenu: some View {
        Menu {
            residencyActions
            Button(project.explicitlyExcluded ? "Include Project" : "Exclude Project") {
                Task {
                    await manager.setProjectExcluded(
                        pairID: pair.id,
                        projectID: project.id,
                        excluded: !project.explicitlyExcluded
                    )
                }
            }
            Button("Edit Rules") { manager.isShowingPairSettings = true }
            if linkNeedsRepair {
                Button("Repair Link") {
                    Task { await manager.repairLink(pairID: pair.id, projectID: project.id) }
                }
            }
            if project.state == .conflict {
                Button("Resolve Conflict") { manager.focusedConflictProjectID = project.id }
            }
            Divider()
            Button("Open Real Location") { manager.open(realLocation) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
        .help("More project actions")
        .accessibilityLabel("More actions for \(project.name)")
    }

    @ViewBuilder
    private var residencyActions: some View {
        switch project.residency {
        case .mirrored, .internalOnlyPendingMirror:
            Button("Move to External") {
                Task { await manager.moveToExternal(pairID: pair.id, projectID: project.id) }
            }
        case .externalResident, .externalOnlyPendingLink:
            Button("Bring Internal") {
                Task { await manager.bringInternal(pairID: pair.id, projectID: project.id) }
            }
        }
    }

    private var realLocation: URL {
        let side: DevSyncSide = project.residency == .externalResident || project.residency == .externalOnlyPendingLink
            ? .external
            : .internal
        return pair.root(for: side).url.appendingPathComponent(project.relativePath, isDirectory: true)
    }

    // MARK: Missing project

    private var missingDecisions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This project is no longer on the internal drive.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(DevMissingProjectDecision.allCases, id: \.self) { decision in
                    Button(decision.displayName) {
                        Task {
                            await manager.decideMissingProject(
                                pairID: pair.id,
                                projectID: project.id,
                                decision: decision
                            )
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

#Preview {
    let manager = DevSyncPreviewFixture.manager()
    let pair = manager.pairs[0]
    return VStack(spacing: 10) {
        ForEach(manager.projects(for: pair.id)) { project in
            DevSyncProjectRow(pair: pair, project: project, manager: manager)
        }
    }
    .padding(20)
    .frame(width: 760)
}

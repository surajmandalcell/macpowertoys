//
//  DevSyncProjectRow.swift
//  powertoys
//

import SwiftUI
import OnePlusUI

struct DevSyncProjectRow: View {
    let pair: DevSyncPair
    let project: DevProject
    let manager: DevSyncManager

    @State private var isShowingDrift = false

    private var driftPaths: [String] { manager.driftPaths[project.id] ?? [] }

    private var linkNeedsRepair: Bool {
        guard let link = manager.link(for: project) else { return false }
        return link.state != .healthy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearSpace.row) {
            identityLine

            ForEach(project.warnings, id: \.self) { warning in
                Label(warning.displayName, systemImage: "exclamationmark.triangle.fill")
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.warning)
            }

            if project.state == .missing {
                missingDecisions
            }
        }
        .padding(.horizontal, OnePlusLinearSpace.section)
        .padding(.vertical, OnePlusLinearSpace.row)
        .frame(minHeight: OnePlusLinearEditorialMetrics.toolRow)
        .linearGroupRowHover()
        .overlay(alignment: .bottom) { OnePlusLinearColor.lineSoft.frame(height: 1) }
    }

    // MARK: Identity

    private var identityLine: some View {
        HStack(spacing: 10) {
            residencyChip
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .linearText()
                Text(project.isRootUnit ? "Files outside repositories" : project.relativePath)
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: OnePlusLinearSpace.row)
            Text(metricsText).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary).lineLimit(1).help(metricsText)
            DevSyncStateBadge(
                icon: project.residency.icon,
                title: project.residency.displayName,
                tint: OnePlusLinearColor.secondary
            )
            DevSyncStateBadge(
                icon: stateIcon,
                title: project.state.displayName,
                tint: project.state.tint
            )
            if !driftPaths.isEmpty { driftButton }
            DevSyncIconButton(icon: "arrow.triangle.2.circlepath", label: "Sync Project") {
                Task { await manager.syncProject(pairID: pair.id, projectID: project.id) }
            }
            DevSyncIconButton(icon: "list.bullet.clipboard", label: "Preview") {
                Task { await manager.previewProject(pairID: pair.id, projectID: project.id) }
            }
            projectMenu
        }
    }

    private var residencyChip: some View {
        Image(systemName: project.residency.icon)
            .linearText(weight: .semibold, color: OnePlusLinearColor.accent)
            .frame(width: OnePlusLinearMetrics.navIcon)
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
                tint: OnePlusLinearColor.warning
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
        .contentShape(Rectangle())
        .accessibilityLabel("Resolve destination drift")
        .popover(isPresented: $isShowingDrift, arrowEdge: .bottom) {
            driftPopover.onePlusFocusPolicy().onePlusOpaquePopover()
        }
    }

    private var driftPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            DevSyncSectionHeader(title: "Drift paths")
            ForEach(driftPaths, id: \.self) { path in
                VStack(alignment: .leading, spacing: 4) {
                    Text(path)
                        .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced))
                        .foregroundStyle(OnePlusLinearColor.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
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
        OnePlusMenuButton("More actions for \(project.displayName)", variant: .borderedIcon) {
            var items: [OnePlusPopupMenuEntry] = []
            if !project.isRootUnit {
                if project.residency == .mirrored || project.residency == .internalOnlyPendingMirror {
                    items.append(.item(.init("Move to External") {
                        Task { await manager.moveToExternal(pairID: pair.id, projectID: project.id) }
                    }))
                } else {
                    items.append(.item(.init("Bring Internal") {
                        Task { await manager.bringInternal(pairID: pair.id, projectID: project.id) }
                    }))
                }
            }
            items.append(.item(.init(project.explicitlyExcluded ? "Include Project" : "Exclude Project") {
                Task { await manager.setProjectExcluded(pairID: pair.id, projectID: project.id, excluded: !project.explicitlyExcluded) }
            }))
            items.append(.item(.init("Edit Rules") { manager.isShowingPairSettings = true }))
            if linkNeedsRepair {
                items.append(.item(.init("Repair Link") { Task { await manager.repairLink(pairID: pair.id, projectID: project.id) } }))
            }
            if project.state == .conflict {
                items.append(.item(.init("Resolve Conflict") { manager.focusedConflictProjectID = project.id }))
            }
            items.append(.separator())
            items.append(.item(.init("Open Real Location") { manager.open(realLocation) }))
            return items
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
                .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
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

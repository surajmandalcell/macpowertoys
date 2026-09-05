//
//  DevSyncSetupSheet.swift
//  powertoys
//

import AppKit
import SwiftUI

enum DevSetupStep: Int, CaseIterable, Identifiable {
    case roots
    case compatibility
    case projects
    case rules
    case activity
    case preview

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .roots: return "Roots"
        case .compatibility: return "Compatibility"
        case .projects: return "What syncs"
        case .rules: return "Rules"
        case .activity: return "Activity"
        case .preview: return "Preview"
        }
    }

    var label: String {
        "Step \(rawValue + 1) of \(DevSetupStep.allCases.count) · \(title)"
    }
}

@MainActor
@Observable
final class DevSyncSetupModel {
    let engine: DevSyncEngine

    var step: DevSetupStep = .roots
    var draft = DevSetupDraft(displayName: "Dev Sync")
    private var previewDraft: DevSetupDraft?
    var probe: DevSetupProbe?
    var groups: [DevSetupProjectGroup] = []
    var preview: DevSetupPreview?
    private(set) var isWorking = false
    var errorBanner: String?

    init(engine: DevSyncEngine) {
        self.engine = engine
    }

    var isLastStep: Bool { step == .preview }

    var primaryActionTitle: String {
        guard isLastStep else { return "Continue" }
        return preview?.summary.primaryActionTitle ?? "Create Pair"
    }

    var canContinue: Bool {
        guard !isWorking else { return false }
        switch step {
        case .roots:
            return probe?.canContinue == true
        case .compatibility:
            return probe?.capabilities.fidelity != .blocked
        case .projects, .rules, .activity:
            return true
        case .preview:
            return preview != nil
        }
    }

    var rootIssues: [String] {
        (probe?.issues ?? []).map(\.message)
    }

    var compatibilityNotes: [String] {
        var notes = probe?.warnings ?? []
        notes.append(contentsOf: probe?.capabilities.rsync?.unsupportedFeatureNotes ?? [])
        return notes
    }

    func isIncluded(_ item: DevSetupProjectItem, in group: DevSetupGroup) -> Bool {
        !draft.excludedProjectPaths.contains(item.relativePath)
    }

    func setIncluded(_ included: Bool, for item: DevSetupProjectItem, in group: DevSetupGroup) {
        if included {
            draft.excludedProjectPaths.remove(item.relativePath)
        } else {
            draft.excludedProjectPaths.insert(item.relativePath)
        }
    }

    func isAdoptingLink(_ item: DevSetupProjectItem) -> Bool {
        draft.adoptedLinkPaths.contains(item.relativePath)
    }

    func setAdoptingLink(_ adopting: Bool, for item: DevSetupProjectItem) {
        if adopting {
            draft.adoptedLinkPaths.insert(item.relativePath)
        } else {
            draft.adoptedLinkPaths.remove(item.relativePath)
        }
    }

    func applyActivityPreset(_ preset: DevActivityPreset) {
        draft.configuration.activityPreset = preset
        draft.configuration.timing = preset.timing
    }

    func probeRoots() async {
        guard let internalURL = draft.internalURL, let externalURL = draft.externalURL else {
            probe = nil
            return
        }
        isWorking = true
        probe = await engine.probeRoots(internal: internalURL, external: externalURL)
        isWorking = false
    }

    func discover() async {
        isWorking = true
        groups = await engine.discover(draft: draft)
        isWorking = false
        let scanDraft = draft
        let scanned = await engine.preview(draft: scanDraft)
        if step == .projects, !scanned.groups.isEmpty { groups = scanned.groups }
        preview = scanned
        previewDraft = scanDraft
    }

    func buildPreview() async {
        if preview != nil, previewDraft == draft { return }
        isWorking = true
        preview = await engine.preview(draft: draft)
        previewDraft = draft
        isWorking = false
    }

    func back() {
        guard let previous = DevSetupStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func advance() async -> DevSyncPair? {
        guard canContinue else { return nil }
        switch step {
        case .roots, .compatibility:
            step = DevSetupStep(rawValue: step.rawValue + 1) ?? step
            if step == .projects { await discover() }
        case .projects, .rules:
            step = DevSetupStep(rawValue: step.rawValue + 1) ?? step
        case .activity:
            step = .preview
            await buildPreview()
        case .preview:
            return await createPair()
        }
        return nil
    }

    private func createPair() async -> DevSyncPair? {
        guard let preview else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            return try await engine.createPair(draft: draft, approvedPreview: preview)
        } catch {
            errorBanner = error.localizedDescription
            LogManager.shared.error("Dev Sync setup failed: \(error)", source: "DevSync")
            return nil
        }
    }
}

// MARK: - Sheet

struct DevSyncSetupSheet: View {
    var manager: DevSyncManager = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var model: DevSyncSetupModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            QuietDivider()

            if let model {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepLabel(model)
                        if let banner = model.errorBanner {
                            DevSyncErrorBanner(message: banner) { model.errorBanner = nil }
                        }
                        DevSyncSetupStepContent(model: model)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .thinScrollIndicators()

                QuietDivider()
                footer(model)
            }
        }
        .frame(width: 560, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard model == nil else { return }
            model = DevSyncSetupModel(engine: manager.engine)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Set Up Dev Sync")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            UtilityModalCloseButton { dismiss() }
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
    }

    private func stepLabel(_ model: DevSyncSetupModel) -> some View {
        HStack(spacing: 8) {
            DevSyncSectionHeader(title: model.step.label)
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Working")
            }
        }
    }

    private func footer(_ model: DevSyncSetupModel) -> some View {
        HStack(spacing: 8) {
            Button("Back") { model.back() }
                .disabled(model.step == .roots || model.isWorking)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task {
                    let created = await model.advance()
                    guard created != nil else { return }
                    await manager.load()
                    dismiss()
                }
            } label: {
                Text(model.primaryActionTitle)
                    .fontWeight(.semibold)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canContinue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Step content

private struct DevSyncSetupStepContent: View {
    @Bindable var model: DevSyncSetupModel

    var body: some View {
        switch model.step {
        case .roots: DevSyncSetupRootsStep(model: model)
        case .compatibility: DevSyncSetupCompatibilityStep(model: model)
        case .projects: DevSyncSetupProjectsStep(model: model)
        case .rules: DevSyncRulesSection(configuration: $model.draft.configuration)
        case .activity: DevSyncActivitySection(configuration: $model.draft.configuration)
        case .preview: DevSyncSetupPreviewStep(model: model)
        }
    }
}

// MARK: - Roots

private struct DevSyncSetupRootsStep: View {
    @Bindable var model: DevSyncSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Pair name", text: $model.draft.displayName)
                .textFieldStyle(.roundedBorder)

            Picker("Mode", selection: $model.draft.mode) {
                ForEach(DevSyncMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(model.draft.mode.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            rootRow(title: "Internal root", url: model.draft.internalURL) { model.draft.internalURL = $0 }
            rootRow(title: "External root", url: model.draft.externalURL) { model.draft.externalURL = $0 }

            if let probe = model.probe {
                volumeCard(title: "Internal", volume: probe.capabilities.internalVolume)
                volumeCard(title: "External", volume: probe.capabilities.externalVolume)
            }

            ForEach(model.rootIssues, id: \.self) { issue in
                DevSyncIssueStrip(message: issue)
            }
        }
        .task(id: rootsKey) { await model.probeRoots() }
    }

    private var rootsKey: String {
        "\(model.draft.internalURL?.path ?? "")|\(model.draft.externalURL?.path ?? "")"
    }

    private func rootRow(title: String, url: URL?, set: @escaping (URL) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Text(url?.path ?? "No folder selected")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(url == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…") {
                guard let chosen = DevSyncSetupSheet.chooseDirectory() else { return }
                set(chosen)
            }
            .controlSize(.small)
            .accessibilityLabel("Choose \(title)")
        }
    }

    @ViewBuilder
    private func volumeCard(title: String, volume: DevVolumeCapabilities?) -> some View {
        if let volume {
            VStack(alignment: .leading, spacing: 6) {
                DevSyncSectionHeader(title: title)
                DevSyncValueRow(label: "Volume", value: volume.volumeName)
                DevSyncValueRow(label: "File system", value: volume.fileSystemType)
                DevSyncValueRow(label: "Available", value: RcloneFormat.bytes(volume.availableCapacity))
                DevSyncValueRow(
                    label: "Encryption",
                    value: volume.isEncrypted == true ? "Encrypted" : "Not encrypted",
                    icon: volume.isEncrypted == true ? "lock.fill" : "lock.open",
                    tint: volume.isEncrypted == true ? .green : .orange
                )
            }
            .utilitySectionCard()
        }
    }
}

// MARK: - Compatibility

private struct DevSyncSetupCompatibilityStep: View {
    @Bindable var model: DevSyncSetupModel

    private var capabilities: DevPairCapabilities { model.probe?.capabilities ?? DevPairCapabilities() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DevSyncValueRow(
                label: "Metadata fidelity",
                value: capabilities.fidelity.displayName,
                icon: capabilities.fidelity == .blocked ? "hand.raised.fill" : "checkmark.circle.fill",
                tint: capabilities.fidelity == .blocked ? .red : .green
            )
            columns
            if let rsync = capabilities.rsync {
                DevSyncValueRow(label: "rsync", value: rsync.versionText)
                DevSyncValueRow(label: "rsync path", value: rsync.executablePath)
            }
            ForEach(model.compatibilityNotes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if capabilities.fidelity == .blocked {
                DevSyncIssueStrip(message: "This pair cannot sync until both drives support the required file features.")
            }
        }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 20) {
            volumeColumn(title: "Internal", volume: capabilities.internalVolume)
            volumeColumn(title: "External", volume: capabilities.externalVolume)
        }
    }

    @ViewBuilder
    private func volumeColumn(title: String, volume: DevVolumeCapabilities?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DevSyncSectionHeader(title: title)
            if let volume {
                DevSyncValueRow(label: "Writable", value: volume.isReadOnly ? "Read only" : "Writable")
                DevSyncValueRow(label: "Case sensitive", value: volume.isCaseSensitive ? "Yes" : "No")
                DevSyncValueRow(label: "Symbolic links", value: volume.supportsSymbolicLinks ? "Supported" : "Not supported")
                DevSyncValueRow(label: "Permissions", value: volume.supportsUnixPermissions ? "Supported" : "Not supported")
                DevSyncValueRow(label: "Time precision", value: "\(volume.modifyWindowSeconds)s")
            } else {
                Text("Not probed")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Projects

private struct DevSyncSetupProjectsStep: View {
    @Bindable var model: DevSyncSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Everything under the internal root syncs. Git repositories sync as units; every other file and folder syncs as one unit. Only the skip list is left out: caches, dependency checkouts, build outputs, and tmp folders. Git-tracked content inside those still syncs. Nested repositories and packages sync as part of the folder or repository that contains them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.groups.isEmpty {
                Text(model.isWorking ? "Looking for repositories…" : "No repositories found in these roots.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    DevSyncSectionHeader(title: group.group.displayName)
                    ForEach(group.items) { item in
                        DevSyncSetupProjectItemRow(model: model, group: group.group, item: item)
                    }
                }
            }
        }
    }
}

private struct DevSyncSetupProjectItemRow: View {
    let model: DevSyncSetupModel
    let group: DevSetupGroup
    let item: DevSetupProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.relativePath.isEmpty ? "Everything else" : item.name)
                    .font(.system(size: 12))

                Spacer(minLength: 8)

                Text(item.residency?.displayName ?? item.candidateKind?.displayName ?? item.kind.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(item.relativePath.isEmpty ? "loose files and folders outside repositories" : item.relativePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if item.includedBytes + item.excludedBytes > 0 {
                Text("included \(RcloneFormat.bytes(item.includedBytes)) · excluded \(RcloneFormat.bytes(item.excludedBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ForEach(item.warnings, id: \.self) { warning in
                Label(warning.displayName, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if let target = item.adoptableLinkTarget {
                Toggle(isOn: Binding(
                    get: { model.isAdoptingLink(item) },
                    set: { model.setAdoptingLink($0, for: item) }
                )) {
                    Text("Adopt link to \(target)")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .utilitySectionCard()
    }
}

// MARK: - Preview step

private struct DevSyncSetupPreviewStep: View {
    @Bindable var model: DevSyncSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let preview = model.preview {
                summaryCard(preview)
                spaceCard(preview)
                if !preview.sensitiveIncludedPaths.isEmpty {
                    sensitiveCard(preview.sensitiveIncludedPaths)
                }
                ForEach(preview.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if !preview.scanComplete {
                    DevSyncIssueStrip(message: "Some folders could not be read. Deletions stay disabled until a complete scan succeeds.")
                }
            } else {
                Text("Building the preview…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryCard(_ preview: DevSetupPreview) -> some View {
        let summary = preview.summary
        let mirrorCount = preview.groups.filter { $0.group == .internalOnly }.flatMap(\.items).filter { model.isIncluded($0, in: .internalOnly) }.count
        return VStack(alignment: .leading, spacing: 6) {
            DevSyncSectionHeader(title: "Planned changes")
            DevSyncValueRow(label: "Projects to mirror", value: "\(mirrorCount)")
            DevSyncValueRow(label: "Copy internal to external", value: "\(summary.copyToExternalCount) · \(RcloneFormat.bytes(summary.copyToExternalBytes))")
            DevSyncValueRow(label: "Copy external to internal", value: "\(summary.copyToInternalCount) · \(RcloneFormat.bytes(summary.copyToInternalBytes))")
            DevSyncValueRow(label: "Managed links", value: "\(summary.managedLinksToCreate)")
            DevSyncValueRow(label: "Retained external only", value: "\(summary.retainedExternalOnlyCount)")
            DevSyncValueRow(label: "Safety moves", value: "\(summary.safetyMoveCount)")
            DevSyncValueRow(label: "Deletions", value: "\(summary.deletionCount)")
            DevSyncValueRow(label: "Conflicts", value: "\(summary.conflictCount)")
            DevSyncValueRow(label: "Blocked paths", value: "\(summary.blockedPathCount)")
            DevSyncValueRow(label: "Sensitive files included", value: "\(summary.sensitiveIncludedCount)")
        }
        .utilitySectionCard()
    }

    private func spaceCard(_ preview: DevSetupPreview) -> some View {
        let required = preview.summary.requiredFreeBytes
        let reserve = max(0, model.draft.configuration.safety.minimumFreeSpaceReserveBytes)
        let fits = preview.availableExternalBytes >= required + reserve
        return VStack(alignment: .leading, spacing: 6) {
            DevSyncSectionHeader(title: "Space")
            DevSyncValueRow(label: "Required", value: RcloneFormat.bytes(required))
            DevSyncValueRow(label: "Kept free", value: RcloneFormat.bytes(reserve))
            DevSyncValueRow(
                label: "Available",
                value: RcloneFormat.bytes(preview.availableExternalBytes),
                icon: fits ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: fits ? .green : .red
            )
        }
        .utilitySectionCard()
    }

    private func sensitiveCard(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DevSyncSectionHeader(title: "Sensitive files included")
            ForEach(paths.prefix(20), id: \.self) { path in
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .utilitySectionCard()
    }
}

// MARK: - Shared strips

struct DevSyncIssueStrip: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

extension DevSyncSetupSheet {
    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

#Preview {
    DevSyncSetupSheet(manager: DevSyncPreviewFixture.manager())
}

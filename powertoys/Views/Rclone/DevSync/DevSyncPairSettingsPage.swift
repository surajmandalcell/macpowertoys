//
//  DevSyncPairSettingsPage.swift
//  powertoys
//

import SwiftUI

struct DevSyncRulesSection: View {
    @Binding var configuration: DevSyncConfiguration

    @State private var isEditingPatterns = false

    private var keepsVersions: Binding<Bool> {
        Binding(
            get: { configuration.safety.retainOverwritesDays > 0 },
            set: { configuration.safety.retainOverwritesDays = $0 ? 7 : 0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            skipRow
            sensitiveRow
            switchRow("Include Git object store", isOn: $configuration.policy.includeGitMetadata)
            switchRow("Include Git LFS objects", isOn: $configuration.policy.includeGitLFSObjects)
            metadataRow(title: "Preserve extended attributes", selection: $configuration.metadata.xattrs)
            metadataRow(title: "Preserve permissions", selection: $configuration.metadata.permissions)
            metadataRow(title: "Preserve hard links", selection: $configuration.metadata.hardLinks)
            switchRow("Keep previous versions", isOn: keepsVersions)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>, disabled: Bool = false, help: String = "") -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .disabled(disabled)
        }
        .help(help)
    }

    @State private var isEditingSkipPatterns = false

    private var skipRow: some View {
        HStack(spacing: 8) {
            Text("Skip caches, dependencies, build outputs, and tmp")
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Button("Extra patterns…") { isEditingSkipPatterns = true }
                .controlSize(.small)
                .popover(isPresented: $isEditingSkipPatterns, arrowEdge: .bottom) {
                    skipPatternEditor
                }
            Toggle("Skip caches, dependencies, build outputs, and tmp", isOn: $configuration.policy.skipCommonCaches)
                .labelsHidden()
        }
        .help("Git-tracked content inside a skipped folder still syncs.")
    }

    private var skipPatternEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DevSyncSectionHeader(title: "Extra skip patterns")
            TextEditor(text: Binding(
                get: { configuration.policy.explicitExcludes.joined(separator: "\n") },
                set: { text in
                    configuration.policy.explicitExcludes = text
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ))
            .thinScrollIndicators()
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(width: 320, height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            Text("One glob per line. A trailing slash matches a folder anywhere. The built-in list already covers node_modules, caches, build outputs, and tmp.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private var sensitiveRow: some View {
        HStack(spacing: 8) {
            Text("Back up ignored sensitive and local files")
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Button("Edit patterns…") { isEditingPatterns = true }
                .controlSize(.small)
                .popover(isPresented: $isEditingPatterns, arrowEdge: .bottom) {
                    patternEditor
                }
            Toggle("Back up ignored sensitive and local files", isOn: $configuration.policy.includeIgnoredSensitiveFiles)
                .labelsHidden()
        }
    }

    private var patternEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DevSyncSectionHeader(title: "Sensitive patterns")
            TextEditor(text: Binding(
                get: { configuration.policy.sensitivePatterns.joined(separator: "\n") },
                set: { text in
                    configuration.policy.sensitivePatterns = text
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ))
            .thinScrollIndicators()
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(width: 320, height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            Text("One glob per line.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func metadataRow(title: String, selection: Binding<DevMetadataOption>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                Text("Auto").tag(DevMetadataOption.auto)
                Text("On").tag(DevMetadataOption.on)
                Text("Off").tag(DevMetadataOption.off)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }
}

struct DevSyncActivitySection: View {
    @Binding var configuration: DevSyncConfiguration

    @State private var isShowingAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Activity", selection: Binding(
                get: { configuration.activityPreset },
                set: { preset in
                    configuration.activityPreset = preset
                    configuration.timing = preset.timing
                }
            )) {
                ForEach(DevActivityPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            DisclosureGroup("Advanced", isExpanded: $isShowingAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    StepperField(label: "Quiet period", value: $configuration.timing.quietPeriodSeconds, range: 0...600, format: .number, suffix: "s")
                    StepperField(label: "Minimum project interval", value: $configuration.timing.minimumProjectIntervalSeconds, range: 0...3_600, format: .number, suffix: "s")
                    StepperField(label: "Activity checkpoint", value: $configuration.timing.continuousCheckpointSeconds, range: 0...7_200, format: .number, suffix: "s")
                    StepperField(label: "Large file quiet period", value: $configuration.timing.largeFileQuietSeconds, range: 0...3_600, format: .number, suffix: "s")
                    StepperField(label: "Large file warning", value: largeFileWarningGigabytes, range: 1...512, format: .number, suffix: "GB")
                    Toggle("Large transfers require power", isOn: $configuration.power.largeTransfersRequirePower)
                .frame(maxWidth: .infinity)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var largeFileWarningGigabytes: Binding<Int> {
        Binding(
            get: { max(1, Int(configuration.performance.largeFileWarningBytes / 1_073_741_824)) },
            set: { configuration.performance.largeFileWarningBytes = Int64($0) * 1_073_741_824 }
        )
    }
}

// MARK: - Page

struct DevSyncPairSettingsPage: View {
    let pair: DevSyncPair
    let manager: DevSyncManager

    @State private var configuration: DevSyncConfiguration?
    @State private var isConfirmingRemoval = false

    var body: some View {
        WorkspacePage("\(pair.displayName) Settings", subtitle: pair.mode.displayName) {
            Button("Done") { manager.isShowingPairSettings = false }
                .buttonStyle(.borderedProminent)
        } content: {
            if let configuration {
                let binding = Binding(
                    get: { configuration },
                    set: { newValue in
                        self.configuration = newValue
                        Task { await manager.updateConfiguration(pairID: pair.id, configuration: newValue) }
                    }
                )
                modeCard
                section("Rules") { DevSyncRulesSection(configuration: binding) }
                section("Activity") { DevSyncActivitySection(configuration: binding) }
                section("Safety") { DevSyncSafetySection(configuration: binding) }
                section("Power") { DevSyncPowerSection(configuration: binding) }
                section("Danger") { dangerRow }
            }
        }
        .onAppear { configuration = pair.configuration }
        .confirmationDialog("Remove \"\(pair.displayName)\"?", isPresented: $isConfirmingRemoval) {
            Button("Remove pair", role: .destructive) {
                Task { await manager.removePair(pairID: pair.id, deleteSafetyStore: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing the pair stops syncing. It keeps every file on both drives and keeps the safety store.")
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            DevSyncSectionHeader(title: "Mode")
            VStack(alignment: .leading, spacing: 6) {
                DevSyncValueRow(label: "Mode", value: pair.mode.displayName)
                Text(pair.mode.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DevSyncValueRow(label: "Internal root", value: pair.internalRoot.path)
                DevSyncValueRow(label: "External root", value: pair.externalRoot.path)
            }
            .utilitySectionCard()
        }
    }

    private var dangerRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remove this pair")
                    .font(.system(size: 12))
                Text("Files stay on both drives. The safety store is kept.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Remove Pair…", role: .destructive) { isConfirmingRemoval = true }
                .controlSize(.small)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DevSyncSectionHeader(title: title)
            content()
                .utilitySectionCard()
        }
    }
}

private struct DevSyncSafetySection: View {
    @Binding var configuration: DevSyncConfiguration

    private var reserveGigabytes: Binding<Int> {
        Binding(
            get: { max(0, Int(configuration.safety.minimumFreeSpaceReserveBytes / 1_073_741_824)) },
            set: { configuration.safety.minimumFreeSpaceReserveBytes = Int64($0) * 1_073_741_824 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepperField(label: "Keep overwritten files", value: $configuration.safety.retainOverwritesDays, range: 0...365, format: .number, suffix: "days")
            StepperField(label: "Keep deleted files", value: $configuration.safety.retainDeletesDays, range: 0...365, format: .number, suffix: "days")
            StepperField(label: "Keep resolved conflicts", value: $configuration.safety.retainResolvedConflictsDays, range: 0...365, format: .number, suffix: "days")
            StepperField(label: "Free space reserve", value: reserveGigabytes, range: 0...512, format: .number, suffix: "GB")
            Toggle("Protect destination changes", isOn: $configuration.safety.protectDestinationDrift)
                .frame(maxWidth: .infinity)
            Toggle("Repair missing links automatically", isOn: $configuration.safety.autoRepairMissingLinks)
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DevSyncPowerSection: View {
    @Binding var configuration: DevSyncConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Pause in Low Power Mode", isOn: $configuration.power.pauseOnLowPowerMode)
                .frame(maxWidth: .infinity)
            Toggle("Large transfers require power", isOn: $configuration.power.largeTransfersRequirePower)
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let manager = DevSyncPreviewFixture.manager()
    return DevSyncPairSettingsPage(pair: manager.pairs[0], manager: manager)
        .frame(width: 760, height: 720)
}

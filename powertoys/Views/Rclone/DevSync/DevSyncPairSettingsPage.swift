//
//  DevSyncPairSettingsPage.swift
//  powertoys
//

import SwiftUI
import OnePlusUI

struct DevSyncRulesSection: View {
    @Binding var configuration: DevSyncConfiguration
    var title: String?

    @State private var isEditingPatterns = false
    @State private var isEditingSkipPatterns = false

    private var keepsVersions: Binding<Bool> {
        Binding(
            get: { configuration.safety.retainOverwritesDays > 0 },
            set: { configuration.safety.retainOverwritesDays = $0 ? 7 : 0 }
        )
    }

    var body: some View {
        RSyncGroup(title: title) {
            OnePlusLinearAppletRow("Skip caches, dependencies, build outputs, and tmp") {
                Button("Extra patterns…") { isEditingSkipPatterns = true }
                    .buttonStyle(OnePlusLinearButtonStyle(.soft))
                    .popover(isPresented: $isEditingSkipPatterns, arrowEdge: .bottom) {
                        patternEditor(
                            "Extra skip patterns",
                            patterns: $configuration.policy.explicitExcludes,
                            help: "One glob per line. A trailing slash matches a folder anywhere. The built-in list already covers node_modules, caches, build outputs, and tmp."
                        ).onePlusOpaquePopover()
                    }
                Toggle("Skip caches, dependencies, build outputs, and tmp", isOn: $configuration.policy.skipCommonCaches)
                    .labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
            }
            .help("Git-tracked content inside a skipped folder still syncs.")
            OnePlusLinearAppletRow("Back up ignored sensitive and local files") {
                Button("Edit patterns…") { isEditingPatterns = true }
                    .buttonStyle(OnePlusLinearButtonStyle(.soft))
                    .popover(isPresented: $isEditingPatterns, arrowEdge: .bottom) {
                        patternEditor("Sensitive patterns", patterns: $configuration.policy.sensitivePatterns, help: "One glob per line.").onePlusOpaquePopover()
                    }
                Toggle("Back up ignored sensitive and local files", isOn: $configuration.policy.includeIgnoredSensitiveFiles)
                    .labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
            }
            RSyncSwitchRow("Include Git object store", isOn: $configuration.policy.includeGitMetadata)
            RSyncSwitchRow("Include Git LFS objects", isOn: $configuration.policy.includeGitLFSObjects)
            metadataRow(title: "Preserve extended attributes", selection: $configuration.metadata.xattrs)
            metadataRow(title: "Preserve permissions", selection: $configuration.metadata.permissions)
            metadataRow(title: "Preserve hard links", selection: $configuration.metadata.hardLinks)
            RSyncSwitchRow("Keep previous versions", isOn: keepsVersions)
        }
    }

    private func patternEditor(_ title: String, patterns: Binding<[String]>, help: String) -> some View {
        patternEditorBody(title, patterns: patterns, help: help).onePlusFocusPolicy()
    }

    private func patternEditorBody(_ title: String, patterns: Binding<[String]>, help: String) -> some View {
        OnePlusLinearAppletSection(title) {
            OnePlusTextEditor(title, text: Binding(
                get: { patterns.wrappedValue.joined(separator: "\n") },
                set: { text in
                    patterns.wrappedValue = text
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ))
            .frame(width: OnePlusLinearControlWidth.regular * 2, height: OnePlusLinearSpace.page * 8)
            .padding(OnePlusLinearMetrics.appletRowPadding)
            .help(help)
        }
        .padding(OnePlusLinearMetrics.appletGutter)
    }

    private func metadataRow(title: String, selection: Binding<DevMetadataOption>) -> some View {
        OnePlusLinearAppletRow(title) {
            OnePlusLinearSegmented(choices: [(DevMetadataOption.auto, "Auto"), (.on, "On"), (.off, "Off")],
                                   selection: selection, accessibilityLabel: title)
        }
    }
}

struct DevSyncActivitySection: View {
    @Binding var configuration: DevSyncConfiguration
    var title: String?

    @State private var isShowingAdvanced = false

    var body: some View {
        RSyncGroup(title: title) {
            OnePlusLinearAppletRow("Activity preset") {
                OnePlusLinearSelect(choices: DevActivityPreset.allCases.map { ($0, $0.displayName) }, selection: Binding(
                    get: { configuration.activityPreset },
                    set: { preset in
                        configuration.activityPreset = preset
                        configuration.timing = preset.timing
                    }
                ), accessibilityLabel: "Activity preset", width: OnePlusLinearControlWidth.wide)
            }
            OnePlusLinearAppletRow("Advanced timing") {
                OnePlusLinearIconButton(
                    systemImage: isShowingAdvanced ? "chevron.up" : "chevron.down",
                    help: isShowingAdvanced ? "Hide advanced timing" : "Show advanced timing",
                    size: OnePlusLinearMetrics.appletRowAction
                ) { isShowingAdvanced.toggle() }
            }
            if isShowingAdvanced {
                StepperField(label: "Quiet period", value: $configuration.timing.quietPeriodSeconds, range: 0...600, format: .number, suffix: "s")
                StepperField(label: "Minimum project interval", value: $configuration.timing.minimumProjectIntervalSeconds, range: 0...3_600, format: .number, suffix: "s")
                StepperField(label: "Activity checkpoint", value: $configuration.timing.continuousCheckpointSeconds, range: 0...7_200, format: .number, suffix: "s")
                StepperField(label: "Large file quiet period", value: $configuration.timing.largeFileQuietSeconds, range: 0...3_600, format: .number, suffix: "s")
                StepperField(label: "Large file warning", value: largeFileWarningGigabytes, range: 1...512, format: .number, suffix: "GB")
                RSyncSwitchRow("Large transfers require power", isOn: $configuration.power.largeTransfersRequirePower)
            }
        }
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
        OnePlusLinearPaneBody {
            if let message = manager.errorBanner {
                OnePlusLinearBanner(.error, title: message) {
                    Button("Dismiss") { manager.errorBanner = nil }
                }
            }
            if let configuration {
                let binding = Binding(
                    get: { configuration },
                    set: { newValue in
                        self.configuration = newValue
                        Task {
                            let saved = await manager.updateConfiguration(pairID: pair.id, configuration: newValue)
                            if !saved, self.configuration == newValue {
                                self.configuration = manager.pairs.first { $0.id == pair.id }?.configuration ?? pair.configuration
                            }
                        }
                    }
                )
                modeCard
                DevSyncRulesSection(configuration: binding, title: "Rules")
                DevSyncActivitySection(configuration: binding, title: "Activity")
                DevSyncSafetySection(configuration: binding)
                DevSyncPowerSection(configuration: binding)
                Button("Remove Pair…", role: .destructive) { isConfirmingRemoval = true }
                    .buttonStyle(OnePlusLinearButtonStyle(.destructive))
                    .help("Files stay on both drives. The safety store is kept.")
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
        OnePlusLinearAppletSection("Mode") {
            OnePlusLinearAppletRow(pair.mode.displayName, detail: pair.mode.summary) { EmptyView() }
            OnePlusLinearAppletRow("Internal root") { LinearCaption(pair.internalRoot.path, monospaced: true) }
            OnePlusLinearAppletRow("External root") { LinearCaption(pair.externalRoot.path, monospaced: true) }
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
        OnePlusLinearAppletSection("Safety") {
            StepperField(label: "Keep overwritten files", value: $configuration.safety.retainOverwritesDays, range: 0...365, format: .number, suffix: "days")
            StepperField(label: "Keep deleted files", value: $configuration.safety.retainDeletesDays, range: 0...365, format: .number, suffix: "days")
            StepperField(label: "Keep resolved conflicts", value: $configuration.safety.retainResolvedConflictsDays, range: 0...365, format: .number, suffix: "days")
            StepperField(label: "Free space reserve", value: reserveGigabytes, range: 0...512, format: .number, suffix: "GB")
            RSyncSwitchRow("Protect destination changes", isOn: $configuration.safety.protectDestinationDrift)
            RSyncSwitchRow("Repair missing links automatically", isOn: $configuration.safety.autoRepairMissingLinks)
        }
    }
}

private struct DevSyncPowerSection: View {
    @Binding var configuration: DevSyncConfiguration

    var body: some View {
        OnePlusLinearAppletSection("Power") {
            RSyncSwitchRow("Pause in Low Power Mode", isOn: $configuration.power.pauseOnLowPowerMode)
            RSyncSwitchRow("Large transfers require power", isOn: $configuration.power.largeTransfersRequirePower)
        }
    }
}

#Preview {
    let manager = DevSyncPreviewFixture.manager()
    return DevSyncPairSettingsPage(pair: manager.pairs[0], manager: manager)
        .frame(width: 760, height: 720)
}

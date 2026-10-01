import Foundation
import OnePlusUI
import SwiftUI

nonisolated enum RcloneBandwidthInput {
    static func error(for value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.lowercased() != "off" else { return nil }
        let pattern = #"^[0-9]+(?:\.[0-9]+)?(?:[KMGTPE]i?)?(?:B)?$"#
        guard value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return "Use a rate such as 10M, 1.5GiB, or off."
        }
        return nil
    }
}

struct RcloneSettingsView: View {
    @AppStorage("tool.rclone.startAtLaunch") private var startAtLaunch = false
    @AppStorage("app.showTray") private var showTray = true
    @AppStorage(RcloneDefaults.ignorePatternsKey) private var ignorePatterns = RcloneDefaults.ignorePatterns
    @AppStorage(RcloneDefaults.transfersKey) private var transfers = RcloneDefaults.transfers
    @AppStorage(RcloneDefaults.checkersKey) private var checkers = RcloneDefaults.checkers
    @AppStorage(RcloneDefaults.bandwidthLimitKey) private var bandwidthLimit = RcloneDefaults.bandwidthLimit
    @AppStorage(RcloneDefaults.defaultOperationKey) private var defaultOperation = RcloneDefaults.defaultOperation
    @AppStorage(RcloneDefaults.maxRetriesKey) private var maxRetries = RcloneDefaults.maxRetries
    @AppStorage(RcloneDefaults.retryBackoffKey) private var retryBackoff = RcloneDefaults.retryBackoff
    @AppStorage(RcloneDefaults.lowLevelRetriesKey) private var lowLevelRetries = RcloneDefaults.lowLevelRetries
    @AppStorage(RcloneDefaults.maxConcurrentJobsKey) private var maxConcurrentJobs = RcloneDefaults.maxConcurrentJobs
    @AppStorage(RcloneDefaults.binaryPathKey) private var binaryPath = RcloneDefaults.binaryPath

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                syncEngineCard
                    .frame(maxWidth: .infinity)
                transfersCard
                    .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            ignorePatternsCard
            retriesCard
            rcloneCard
        }
        .onChange(of: startAtLaunch) { _, enabled in
            Task { await RcloneJobManager.shared.backgroundPreferenceDidChange(enabled: enabled) }
        }
    }

    private var syncEngineCard: some View {
        OnePlusCard {
            VStack(spacing: 0) {
                OnePlusCardHeader("Sync engine")
                OnePlusSettingRow("Start at launch", help: "Ready after sign-in.") {
                    Toggle("Start at launch", isOn: $startAtLaunch).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Show transfer status", help: "In the MacPowerToys menu bar.") {
                    Toggle("Show transfer status", isOn: $showTray).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Retry interrupted transfers", help: "Always on; unfinished transfers resume.", separator: false) {
                    Text("On").onePlusText(.control)
                }
            }
        }
    }

    private var transfersCard: some View {
        OnePlusCard {
            VStack(spacing: 0) {
                OnePlusCardHeader("Transfers")
                OnePlusSettingRow("Parallel transfers", help: "Files copied at the same time.", controlWidth: OnePlusMetrics.wideControlColumn) {
                    OnePlusStepperField("Parallel transfers", value: $transfers, in: 1...64)
                }
                OnePlusSettingRow("Checkers", help: "Remote checks at the same time.", controlWidth: OnePlusMetrics.wideControlColumn) {
                    OnePlusStepperField("Checkers", value: $checkers, in: 1...128)
                }
                OnePlusSettingRow("Bandwidth limit", help: "Leave blank or enter off for no limit.", controlWidth: OnePlusMetrics.wideControlColumn) {
                    OnePlusTextField("10M, 1.5GiB, or off", text: $bandwidthLimit, error: RcloneBandwidthInput.error(for: bandwidthLimit))
                }
                OnePlusSettingRow("Default operation", controlWidth: OnePlusMetrics.wideControlColumn, separator: false) {
                    OnePlusSelect(
                        choices: RcloneOperation.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: $defaultOperation,
                        width: OnePlusMetrics.wideControlColumn,
                        accessibilityLabel: "Default operation"
                    )
                }
            }
        }
    }

    private var ignorePatternsCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Ignore patterns")
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[2]) {
                OnePlusTextEditor("Ignore patterns", text: $ignorePatterns)
                    .frame(height: OnePlusMetrics.spacing[6] * 8)
                    .help("One glob per line. Used as an exclude rule.")
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }

    private var retriesCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Retries")
            OnePlusSettingRow("Max retries", controlWidth: OnePlusMetrics.wideControlColumn) {
                OnePlusStepperField("Max retries", value: $maxRetries, in: 0...20)
            }
            OnePlusSettingRow("Retry backoff", help: "The wait doubles after each failed try.", controlWidth: OnePlusMetrics.wideControlColumn) {
                OnePlusStepperField(
                    "Retry backoff",
                    value: Binding(get: { Int(retryBackoff) }, set: { retryBackoff = Double($0) }),
                    in: 0...300,
                    unit: "s"
                )
            }
            OnePlusSettingRow("Low-level retries", controlWidth: OnePlusMetrics.wideControlColumn) {
                OnePlusStepperField("Low-level retries", value: $lowLevelRetries, in: 1...50)
            }
            OnePlusSettingRow("Concurrent jobs", controlWidth: OnePlusMetrics.wideControlColumn, separator: false) {
                OnePlusStepperField("Concurrent jobs", value: $maxConcurrentJobs, in: 1...16)
            }
        }
    }

    private var rcloneCard: some View {
        OnePlusCard {
            OnePlusCardHeader("rclone")
            OnePlusSettingRow("Binary path", help: "Leave blank to use the detected binary.", controlWidth: OnePlusMetrics.wideControlColumn, separator: false) {
                OnePlusTextField("Auto-detected", text: $binaryPath)
            }
        }
    }
}

struct StepperField<Value: Strideable, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let label: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let format: Format
    var suffix: String? = nil

    var body: some View {
        HStack(spacing: OnePlusMetrics.spacing[2]) {
            Text(label).onePlusText(.row)
            Spacer(minLength: OnePlusMetrics.spacing[2])
            TextField(label, value: $value, format: format)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onePlusText(.control)
                .padding(.horizontal, OnePlusMetrics.spacing[2])
                .frame(width: OnePlusMetrics.spacing[8] * 2, height: OnePlusMetrics.controlHeight)
                .background(OnePlusColor.field, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
                .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius).strokeBorder(OnePlusColor.line) }
            if let suffix { Text(suffix).onePlusText(.mono).foregroundStyle(OnePlusColor.secondary) }
            Stepper(label, value: $value, in: range).labelsHidden()
        }
        .onChange(of: value) { _, newValue in
            if newValue < range.lowerBound { value = range.lowerBound }
            else if newValue > range.upperBound { value = range.upperBound }
        }
    }
}

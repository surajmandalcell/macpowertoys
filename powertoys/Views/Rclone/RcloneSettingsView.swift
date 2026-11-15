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
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
            syncEngineSection
            transfersSection
            ignorePatternsSection
            retriesSection
            binarySection
        }
        .onChange(of: startAtLaunch) { _, enabled in
            Task { await RcloneJobManager.shared.backgroundPreferenceDidChange(enabled: enabled) }
        }
    }

    private var syncEngineSection: some View {
        OnePlusLinearAppletSection("Sync engine") {
            OnePlusLinearAppletRow("Start at launch", detail: "Ready after sign-in.") {
                Toggle("Start at launch", isOn: $startAtLaunch).labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
            }
            OnePlusLinearAppletRow("Show transfer status", detail: "In the MacPowerToys menu bar.") {
                Toggle("Show transfer status", isOn: $showTray).labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
            }
            OnePlusLinearAppletRow("Retry interrupted transfers", value: "On")
                .help("Always on; unfinished transfers resume.")
        }
    }

    private var transfersSection: some View {
        OnePlusLinearAppletSection("Transfers") {
            OnePlusLinearAppletRow("Parallel transfers", detail: "Files copied at the same time.") {
                OnePlusStepperField("Parallel transfers", value: $transfers, in: 1...64)
            }
            OnePlusLinearAppletRow("Checkers", detail: "Remote checks at the same time.") {
                OnePlusStepperField("Checkers", value: $checkers, in: 1...128)
            }
            OnePlusLinearAppletRow("Bandwidth limit", detail: "Leave blank or enter off for no limit.") {
                OnePlusLinearTextField("10M, 1.5GiB, or off", text: $bandwidthLimit, error: RcloneBandwidthInput.error(for: bandwidthLimit))
                    .frame(width: OnePlusMetrics.wideControlColumn)
            }
            OnePlusLinearAppletRow("Default operation") {
                OnePlusLinearSelect(
                    choices: RcloneOperation.allCases.map { ($0.rawValue, $0.displayName) },
                    selection: $defaultOperation,
                    accessibilityLabel: "Default operation",
                    width: OnePlusMetrics.wideControlColumn
                )
            }
        }
    }

    private var ignorePatternsSection: some View {
        OnePlusLinearAppletSection("Ignore patterns") {
            OnePlusTextEditor("Ignore patterns", text: $ignorePatterns)
                .frame(height: OnePlusMetrics.spacing[6] * 8)
                .help("One glob per line. Used as an exclude rule.")
                .padding(OnePlusLinearMetrics.appletRowPadding)
        }
    }

    private var retriesSection: some View {
        OnePlusLinearAppletSection("Retries") {
            OnePlusLinearAppletRow("Max retries") {
                OnePlusStepperField("Max retries", value: $maxRetries, in: 0...20)
            }
            OnePlusLinearAppletRow("Retry backoff", detail: "The wait doubles after each failed try.") {
                OnePlusStepperField(
                    "Retry backoff",
                    value: Binding(get: { Int(retryBackoff) }, set: { retryBackoff = Double($0) }),
                    in: 0...300,
                    unit: "s"
                )
            }
            OnePlusLinearAppletRow("Low-level retries") {
                OnePlusStepperField("Low-level retries", value: $lowLevelRetries, in: 1...50)
            }
            OnePlusLinearAppletRow("Concurrent jobs") {
                OnePlusStepperField("Concurrent jobs", value: $maxConcurrentJobs, in: 1...16)
            }
        }
    }

    private var binarySection: some View {
        OnePlusLinearAppletSection("rclone binary") {
            OnePlusLinearAppletRow("rclone binary path", detail: "Leave blank to use the detected binary.") {
                OnePlusLinearTextField("Auto-detected", text: $binaryPath)
                    .frame(width: OnePlusMetrics.wideControlColumn)
                    .accessibilityLabel("rclone binary path")
            }
        }
    }
}

/// A whole-number setting row in a filled group: the label and the shared stepper field.
struct StepperField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String?

    init(label: String, value: Binding<Int>, range: ClosedRange<Int>, format: IntegerFormatStyle<Int> = .number, suffix: String? = nil) {
        self.label = label; _value = value; self.range = range; self.suffix = suffix
    }

    /// Settings stored as `Double` (seconds) step in whole units.
    init(label: String, value: Binding<Double>, range: ClosedRange<Double>,
         format: FloatingPointFormatStyle<Double> = .number, suffix: String? = nil) {
        self.label = label
        _value = Binding(get: { Int(value.wrappedValue.rounded()) }, set: { value.wrappedValue = Double($0) })
        self.range = Int(range.lowerBound)...Int(range.upperBound)
        self.suffix = suffix
    }

    var body: some View {
        OnePlusLinearAppletRow(label) {
            OnePlusStepperField(label, value: $value, in: range, unit: suffix)
        }
    }
}

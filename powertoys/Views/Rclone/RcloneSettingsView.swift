//
//  RcloneSettingsView.swift
//  powertoys
//

import SwiftUI

struct RcloneSettingsView: View {
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
        Group {
            settingsSection("Ignore Patterns") {
                TextEditor(text: $ignorePatterns)
                    .thinScrollIndicators()
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("One glob per line. Applied as --exclude rules on every transfer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            settingsSection("Transfers") {
                StepperField(label: "Parallel transfers", value: $transfers, range: 1...64, format: .number)
                StepperField(label: "Checkers", value: $checkers, range: 1...128, format: .number)
                HStack {
                    Text("Bandwidth limit")
                    Spacer()
                    TextField("Bandwidth limit", text: $bandwidthLimit, prompt: Text("e.g. 10M, off"))
                        .labelsHidden()
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 140)
                }
                HStack {
                    Text("Default operation")
                    Spacer()
                    Picker("Default operation", selection: $defaultOperation) {
                        ForEach(RcloneOperation.allCases) { operation in
                            Text(operation.displayName).tag(operation.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                Text("Number of files moved in parallel and hashed for comparison.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            settingsSection("Retries") {
                StepperField(label: "Max retries", value: $maxRetries, range: 0...20, format: .number)
                StepperField(label: "Retry backoff", value: $retryBackoff, range: 0...300, format: .number, suffix: "s")
                StepperField(label: "Low-level retries", value: $lowLevelRetries, range: 1...50, format: .number)
                StepperField(label: "Concurrent jobs", value: $maxConcurrentJobs, range: 1...16, format: .number)
                Text("Failed transfers retry with exponential backoff before giving up.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            settingsSection("rclone") {
                HStack {
                    Text("Binary path")
                    Spacer()
                    TextField("Binary path", text: $binaryPath, prompt: Text("auto-detected"))
                        .labelsHidden()
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minWidth: 180)
                }
                Text("Leave empty to locate rclone on the system PATH.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).utilitySectionHeader()
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12))
            .controlSize(.small)
            .utilitySectionCard()
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
        HStack(spacing: 8) {
            Text(label)
            Spacer()
            TextField("", value: $value, format: format)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if let suffix {
                Text(suffix)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
        .onChange(of: value) { _, newValue in
            if newValue < range.lowerBound {
                value = range.lowerBound
            } else if newValue > range.upperBound {
                value = range.upperBound
            }
        }
    }
}

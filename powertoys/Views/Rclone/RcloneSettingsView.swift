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
            Section {
                TextEditor(text: $ignorePatterns)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("One glob per line. Applied as --exclude rules on every transfer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ignore Patterns")
            }

            Section {
                Stepper(value: $transfers, in: 1...64) {
                    LabeledContent("Parallel transfers", value: "\(transfers)")
                }
                Stepper(value: $checkers, in: 1...128) {
                    LabeledContent("Checkers", value: "\(checkers)")
                }
                TextField("Bandwidth limit", text: $bandwidthLimit, prompt: Text("e.g. 10M, off"))
                    .font(.system(size: 12, design: .monospaced))
                Picker("Default operation", selection: $defaultOperation) {
                    ForEach(RcloneOperation.allCases) { operation in
                        Text(operation.displayName).tag(operation.rawValue)
                    }
                }
            } header: {
                Text("Transfers")
            } footer: {
                Text("Number of files moved in parallel and hashed for comparison.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $maxRetries, in: 0...20) {
                    LabeledContent("Max retries", value: "\(maxRetries)")
                }
                Stepper(value: $retryBackoff, in: 0...300, step: 1) {
                    LabeledContent("Retry backoff", value: "\(Int(retryBackoff))s")
                }
                Stepper(value: $lowLevelRetries, in: 1...50) {
                    LabeledContent("Low-level retries", value: "\(lowLevelRetries)")
                }
                Stepper(value: $maxConcurrentJobs, in: 1...16) {
                    LabeledContent("Concurrent jobs", value: "\(maxConcurrentJobs)")
                }
            } header: {
                Text("Retries")
            } footer: {
                Text("Failed transfers retry with exponential backoff before giving up.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Binary path", text: $binaryPath, prompt: Text("auto-detected"))
                    .font(.system(size: 12, design: .monospaced))
            } header: {
                Text("rclone")
            } footer: {
                Text("Leave empty to locate rclone on the system PATH.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

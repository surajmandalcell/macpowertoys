//
//  TransferRecord.swift
//  powertoys
//

import Foundation
import SwiftData

@Model
final class TransferRecord {
    @Attribute(.unique) var id: UUID
    var jobId: UUID
    var operationRaw: String
    var kindRaw: String
    var stateRaw: String
    var sourceFs: String
    var destinationFs: String
    var sourceDisplay: String
    var destinationDisplay: String
    var excludePatterns: String
    var errorMessage: String?
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var bytes: Int64
    var totalBytes: Int64
    var filesTransferred: Int
    var totalFiles: Int
    var attempts: Int
    var averageSpeed: Double

    init(job: TransferJob) {
        self.id = UUID()
        self.jobId = job.id
        self.operationRaw = job.operation.rawValue
        self.kindRaw = job.kind.rawValue
        self.stateRaw = job.state.rawValue
        self.sourceFs = job.sourceFs
        self.destinationFs = job.destinationFs
        self.sourceDisplay = job.sourceDisplay
        self.destinationDisplay = job.destinationDisplay
        self.excludePatterns = job.excludePatterns.joined(separator: "\n")
        self.errorMessage = job.errorMessage
        self.createdAt = job.createdAt
        self.startedAt = job.startedAt
        self.finishedAt = job.finishedAt
        self.bytes = job.displayBytes
        self.totalBytes = job.stats.totalBytes
        self.filesTransferred = job.displayFiles
        self.totalFiles = job.stats.totalTransfers
        self.attempts = job.attempt
        if let duration = job.duration, duration > 0 {
            self.averageSpeed = Double(job.stats.bytes) / duration
        } else {
            self.averageSpeed = 0
        }
    }

    var operation: RcloneOperation { RcloneOperation(rawValue: operationRaw) ?? .copy }
    var state: TransferState { TransferState(rawValue: stateRaw) ?? .completed }
    var kind: TransferKind { TransferKind(rawValue: kindRaw) ?? .directory }
    var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}

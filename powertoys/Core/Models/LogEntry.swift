//
//  LogEntry.swift
//  powertoys
//

import Foundation
import SwiftData

@Model
final class LogEntry {
    var id: UUID
    var timestamp: Date
    var level: Int
    var source: String
    var message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), level: Int, source: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
    }
}

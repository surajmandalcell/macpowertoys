import Foundation

enum AwakeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case passive
    case indefinite
    case timed
    case until

    var id: String { rawValue }
    var title: String {
        switch self {
        case .passive: "Passive"
        case .indefinite: "Keep Awake Indefinitely"
        case .timed: "Keep Awake for an Interval"
        case .until: "Keep Awake Until"
        }
    }
}

struct AwakeConfiguration: Codable, Equatable, Sendable {
    var mode: AwakeMode = .passive
    var keepDisplayOn = false
    var expiresAt: Date?
    var intervalSeconds: TimeInterval = 30 * 60
    var attachedProcessID: Int32?
    var presets: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60, 2 * 60 * 60]
}

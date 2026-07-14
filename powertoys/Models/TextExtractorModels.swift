import Foundation

enum TextRecognitionSpeed: String, CaseIterable, Codable, Identifiable, Sendable {
    case accurate
    case fast
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TextExtractorSettings: Codable, Equatable, Sendable {
    var speed: TextRecognitionSpeed = .accurate
    var languageCorrection = true
    var preferredLanguages: [String] = []
}

struct TextExtraction: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    var needsExpandedView: Bool {
        text.count > 180 || text.filter(\.isNewline).count > 3
    }
}

enum TextExtractorState: Equatable {
    case idle
    case selecting
    case recognizing
    case copied(String)
    case failed(String)
}

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

enum TextExtractorState: Equatable {
    case idle
    case selecting
    case recognizing
    case copied(String)
    case failed(String)
}

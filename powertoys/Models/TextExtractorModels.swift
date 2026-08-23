import Foundation

enum TextRecognitionSpeed: String, CaseIterable, Codable, Identifiable, Sendable {
    case accurate
    case fast
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TextExtractorSettings: Codable, Equatable, Sendable {
    var speed: TextRecognitionSpeed = .fast
    var languageCorrection = true
    var preferredLanguages: [String] = []
    var detectCodes = true

    init(
        speed: TextRecognitionSpeed = .fast,
        languageCorrection: Bool = true,
        preferredLanguages: [String] = [],
        detectCodes: Bool = true
    ) {
        self.speed = speed
        self.languageCorrection = languageCorrection
        self.preferredLanguages = preferredLanguages
        self.detectCodes = detectCodes
    }

    private enum CodingKeys: String, CodingKey {
        case speed, languageCorrection, preferredLanguages, detectCodes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        speed = try values.decodeIfPresent(TextRecognitionSpeed.self, forKey: .speed) ?? .fast
        languageCorrection = try values.decodeIfPresent(Bool.self, forKey: .languageCorrection) ?? true
        preferredLanguages = try values.decodeIfPresent([String].self, forKey: .preferredLanguages) ?? []
        detectCodes = try values.decodeIfPresent(Bool.self, forKey: .detectCodes) ?? true
    }
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

    var openableURL: URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil
        else { return nil }
        return url
    }

    func relativeTimestamp(at now: Date = Date()) -> String {
        guard abs(createdAt.timeIntervalSince(now)) >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: createdAt, relativeTo: now)
    }
}

enum TextExtractorState: Equatable {
    case idle
    case selecting
    case recognizing
    case copied(String)
    case failed(String)
}

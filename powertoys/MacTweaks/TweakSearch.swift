import Foundation

enum TweakSearch {
    static let micLock = TweakItem(
        id: "mic-lock", title: "Mic Lock", category: "Input", kind: .helper,
        summary: "Keep a preferred microphone selected when a headset connects.",
        keywords: ["microphone", "bluetooth", "airpods", "input", "audio", "mute", "volume", "fallback"],
        patterns: ["headset keeps taking microphone", "keep mac mic selected", "bluetooth audio quality"]
    )

    static func results(for query: String, in items: [TweakItem] = [micLock] + TweakCatalog.items) -> [TweakItem] {
        let query = normalize(query)
        guard !query.isEmpty else { return items }
        let terms = words(query)
        return items.compactMap { item -> (TweakItem, Int)? in
            let title = normalize(item.title)
            let allFields: [(String, Int)] =
                [(title, 120), (normalize(item.category), 15), (normalize(item.summary), 22)] +
                item.keywords.map { (normalize($0), 65) } + item.patterns.map { (normalize($0), 45) }
            var score = title == query ? 1000 : (title.hasPrefix(query) ? 400 : 0)
            if item.patterns.contains(where: { normalize($0).contains(query) }) { score += 90 }
            for term in terms {
                let best = allFields.map { field, weight in
                    if field == term { return weight + 80 }
                    if words(field).contains(term) { return weight + 55 }
                    if field.hasPrefix(term) || words(field).contains(where: { $0.hasPrefix(term) }) { return weight + 20 }
                    if field.contains(term) { return weight }
                    let distance = words(field).map { typoDistance(term, $0) }.min() ?? 3
                    return distance == 1 ? weight / 2 : (distance == 2 && term.count >= 6 ? weight / 4 : 0)
                }.max() ?? 0
                guard best > 0 else { return nil }
                score += best
            }
            return (item, score)
        }
        .sorted { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 > $1.1 }
        .map(\.0)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    // A bounded Damerau distance handles single substitutions and swapped letters in short queries.
    private static func typoDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard a.count >= 3, b.count >= 3, abs(a.count - b.count) <= 2 else { return 3 }
        var previousPrevious = Array(0...b.count)
        var previous = previousPrevious
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
            }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count]
    }
}

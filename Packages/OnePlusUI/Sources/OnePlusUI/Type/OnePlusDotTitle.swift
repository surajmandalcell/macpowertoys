import SwiftUI

public struct OnePlusDotTitle: View {
    public nonisolated static let lineHeight: CGFloat = 20
    private let text: String
    private let height: CGFloat
    private let dotRatio: CGFloat
    @Environment(\.displayScale) private var displayScale
    public init(_ text: String, height: CGFloat = Self.lineHeight, dotRatio: CGFloat = 0.74) {
        self.text = text; self.height = height; self.dotRatio = dotRatio
    }
    public var body: some View {
        let drawing = OnePlusDotGlyphs.drawing(text, height: height, scale: displayScale, dotRatio: dotRatio)
        Canvas { context, _ in context.fill(drawing.path, with: .color(OnePlusColor.ink)) }
            .frame(width: drawing.width, height: height)
            .accessibilityElement(children: .ignore).accessibilityLabel(text).accessibilityAddTraits(.isHeader)
    }
}

@MainActor
enum OnePlusDotGlyphs {
    static let glyphs: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["111", "010", "010", "010", "010", "010", "111"],
        "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["010", "110", "010", "010", "010", "010", "111"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
        "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
        "-": ["000", "000", "000", "111", "000", "000", "000"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        "/": ["00001", "00001", "00010", "00100", "01000", "10000", "10000"],
        "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"]
    ]
    final class Drawing {
        let path: Path
        let width: CGFloat
        init(path: Path, width: CGFloat) { self.path = path; self.width = width }
    }
    private static let cache: NSCache<NSString, Drawing> = {
        let cache = NSCache<NSString, Drawing>(); cache.countLimit = 128; return cache
    }()
    static func drawing(_ text: String, height: CGFloat, scale: CGFloat, dotRatio: CGFloat = 0.74) -> Drawing {
        let key = "\(text.uppercased())|\(height)|\(scale)|\(dotRatio)" as NSString
        if let drawing = cache.object(forKey: key) { return drawing }
        let unit = height / 7
        var path = Path()
        var x = 0
        for character in text.uppercased() {
            let glyph = glyphs[character] ?? glyphs["?"]!
            for (row, line) in glyph.enumerated() {
                for (column, bit) in line.enumerated() where bit == "1" {
                    let diameter = unit * dotRatio
                    path.addEllipse(in: CGRect(x: (CGFloat(x + column) + 0.5) * unit - diameter / 2,
                                               y: (CGFloat(row) + 0.5) * unit - diameter / 2,
                                               width: diameter, height: diameter))
                }
            }
            x += (glyph.first?.count ?? 5) + 1
        }
        let drawing = Drawing(path: path, width: CGFloat(max(x - 1, 0)) * unit)
        cache.setObject(drawing, forKey: key)
        return drawing
    }
}

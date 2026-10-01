import Foundation
import XCTest
@testable import OnePlusUI

final class OnePlusMotionTests: XCTestCase {
    func testCustomMotionIsInstantInBothAccessibilityModes() {
        XCTAssertEqual(OnePlusMotion.hover, 0)
        XCTAssertEqual(OnePlusMotion.selection, 0)
        XCTAssertEqual(OnePlusMotion.content, 0)
        for reduceMotion in [false, true] {
            for duration in [0.0, 0.1, 1.0] {
                XCTAssertNil(OnePlusMotion.animation(reduceMotion: reduceMotion, duration: duration))
            }
        }
    }

    func testSharedHoverSourcesHaveNoMotionOrGeometryEffects() throws {
        let forbidden = try NSRegularExpression(pattern: #"\.\s*(animation|transition|contentTransition|scaleEffect|offset|matchedGeometryEffect)\s*\(|\bwithAnimation\s*\(|\bNSAnimationContext\b|\.\s*animator\s*\("#)
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/OnePlusUI")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains(".onHover") || source.contains("func mouseEntered(") else { continue }
            XCTAssertNil(forbidden.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), file.path)
        }
        for regression in [".scaleEffect(hover ? 1.01 : 1)", ".offset(x: hover ? 2 : 0)", ".animation(.easeInOut, value: hover)"] {
            XCTAssertNotNil(forbidden.firstMatch(in: regression, range: NSRange(regression.startIndex..., in: regression)))
        }
    }
}

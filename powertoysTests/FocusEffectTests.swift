import XCTest

final class FocusEffectTests: XCTestCase {
    func testCustomButtonStylesSuppressTheMismatchedSystemOutline() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys/Views", isDirectory: true)
        let swiftFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )?.allObjects as? [URL]
        ).filter { $0.pathExtension == "swift" }

        for file in swiftFiles {
            let lines = String(decoding: try Data(contentsOf: file), as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for index in lines.indices where
                lines[index].contains(".buttonStyle(.plain)")
                || lines[index].contains(".buttonStyle(.borderless)") {
                let end = min(index + 9, lines.endIndex)
                XCTAssertTrue(
                    lines[index..<end].contains { $0.contains(".focusEffectDisabled()") },
                    "Custom control in \(file.lastPathComponent):\(index + 1) has the mismatched system outline."
                )
            }
        }
    }
}

import SwiftUI
import XCTest
@testable import powertoys

final class FocusEffectTests: XCTestCase {
    @MainActor
    func testSharedRootSuppressesDescendantFocusEffects() {
        var focusEffectEnabled = true
        let host = NSHostingView(rootView: FocusEffectProbe { focusEffectEnabled = $0 }
            .utilityMotionPolicy())
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(focusEffectEnabled)
    }

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

private struct FocusEffectProbe: View {
    @Environment(\.isFocusEffectEnabled) private var isFocusEffectEnabled
    let onAppear: (Bool) -> Void

    var body: some View {
        Button("Probe") {}
            .onAppear { onAppear(isFocusEffectEnabled) }
    }
}

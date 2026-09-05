import AppKit
import XCTest
@testable import powertoys

@MainActor
final class UtilityModelTests: XCTestCase {
    func testColorCopyFormatTitlesAreHumanReadable() {
        XCTAssertEqual(ColorCopyFormat.hex.title, "HEX")
        XCTAssertEqual(ColorCopyFormat.cssVariable.title, "CSS Variable")
        XCTAssertEqual(ColorCopyFormat.swiftUI.title, "SwiftUI")
        XCTAssertEqual(ColorCopyFormat.nsColor.title, "NSColor")
    }

    func testColorFormattingCoversEveryOutputFormat() {
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 0.25)
        XCTAssertEqual(sample.string(.hex), "#FF8000")
        XCTAssertEqual(sample.string(.hexa), "#FF800040")
        XCTAssertEqual(sample.string(.rgb), "rgb(255, 128, 0)")
        XCTAssertEqual(sample.string(.rgba), "rgba(255, 128, 0, 0.25)")
        XCTAssertEqual(sample.string(.hsl), "hsl(30, 100%, 50%)")
        XCTAssertEqual(sample.string(.hsla), "hsla(30, 100%, 50%, 0.25)")
        XCTAssertEqual(sample.string(.cssVariable), "--color: #FF800040;")
        XCTAssertEqual(sample.string(.swiftUI), "Color(red: 1, green: 0.5, blue: 0, opacity: 0.25)")
        XCTAssertEqual(sample.string(.nsColor), "NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.25)")
    }

    func testColorHSLConversionCoversGrayRedGreenAndBlueBranches() {
        XCTAssertEqual(ColorSample(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).string(.hsl), "hsl(0, 0%, 50%)")
        XCTAssertEqual(ColorSample(red: 1, green: 0, blue: 0, alpha: 1).string(.hsl), "hsl(0, 100%, 50%)")
        XCTAssertEqual(ColorSample(red: 0, green: 1, blue: 0, alpha: 1).string(.hsl), "hsl(120, 100%, 50%)")
        XCTAssertEqual(ColorSample(red: 0, green: 0, blue: 1, alpha: 1).string(.hsl), "hsl(240, 100%, 50%)")
        XCTAssertEqual(ColorSample(red: 1, green: 0, blue: 0.5, alpha: 1).string(.hsl), "hsl(330, 100%, 50%)")
    }

    func testColorMatchingUsesStrictToleranceAcrossAllChannels() {
        let sample = ColorSample(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        XCTAssertTrue(sample.matches(ColorSample(red: 0.1004, green: 0.2004, blue: 0.3004, alpha: 0.4004)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0.1005, green: 0.2, blue: 0.3, alpha: 0.4)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.41)))
    }

    func testAwakeModesHaveStableTitlesAndConfigurationDefaults() {
        XCTAssertEqual(AwakeMode.allCases.map(\.title), [
            "Off", "Keep Awake Indefinitely", "Keep Awake for an Interval", "Keep Awake Until"
        ])
        let configuration = AwakeConfiguration()
        XCTAssertEqual(configuration.mode, .passive)
        XCTAssertFalse(configuration.keepDisplayOn)
        XCTAssertNil(configuration.expiresAt)
        XCTAssertEqual(configuration.intervalSeconds, 1_800)
        XCTAssertEqual(configuration.presets, [900, 1_800, 3_600, 7_200])
    }

    func testAwakeQuickModeMatchesOnlyExactTrayPresets() {
        XCTAssertEqual(AwakeQuickMode(configuration: AwakeConfiguration()), .off)

        var configuration = AwakeConfiguration(mode: .indefinite)
        XCTAssertEqual(AwakeQuickMode(configuration: configuration), .indefinite)

        configuration.mode = .timed
        configuration.intervalSeconds = 1_800
        XCTAssertEqual(AwakeQuickMode(configuration: configuration), .thirtyMinutes)

        configuration.intervalSeconds = 3_600
        XCTAssertEqual(AwakeQuickMode(configuration: configuration), .oneHour)

        configuration.intervalSeconds = 900
        XCTAssertEqual(AwakeQuickMode(configuration: configuration), .custom)

        configuration.mode = .until
        XCTAssertEqual(AwakeQuickMode(configuration: configuration), .custom)
    }

    func testTrayPopoverKeepsTabAndVerticalInsetsBalanced() {
        let availableWidth: CGFloat = 308
        let tabWidth = TrayPopoverLayout.tabWidth(availableWidth: availableWidth, count: 2)

        XCTAssertEqual(tabWidth * 2 + TrayPopoverLayout.tabSpacing, availableWidth, accuracy: 0.001)
        XCTAssertTrue(TrayPopoverLayout.showsTabLabels(count: 2))
        XCTAssertFalse(TrayPopoverLayout.showsTabLabels(count: 3))
        XCTAssertEqual(TrayPopoverLayout.tabHeight, 28)
        XCTAssertEqual(TrayPopoverLayout.tabGroupInset, 4)
        XCTAssertEqual(TrayPopoverLayout.tabGroupOuterInset, 8)
        XCTAssertEqual(TrayPopoverLayout.bodyTopInset, 0)
        XCTAssertGreaterThan(TrayPopoverLayout.bodyBottomInset, TrayPopoverLayout.bodyTopInset)
        XCTAssertGreaterThan(TrayPopoverLayout.footerBottomInset, TrayPopoverLayout.footerTopInset)
        XCTAssertEqual(
            TrayPopoverLayout.normalizedSelection("awake", availableIDs: ["rclone", "awake"]),
            "awake"
        )
        XCTAssertEqual(
            TrayPopoverLayout.normalizedSelection("missing", availableIDs: ["rclone", "awake"]),
            "rclone"
        )
        XCTAssertNil(TrayPopoverLayout.normalizedSelection("awake", availableIDs: []))
    }

    func testTrayTabsUseSharedMotionAndVisiblePressedFeedback() {
        XCTAssertEqual(TrayPopoverLayout.tabTransitionDuration, UtilityMotion.standardDuration)
        XCTAssertEqual(
            TrayTabButtonStyle.backgroundOpacity(
                isSelected: false,
                isHovering: false,
                isPressed: false
            ),
            0
        )
        XCTAssertEqual(
            TrayTabButtonStyle.backgroundOpacity(
                isSelected: false,
                isHovering: true,
                isPressed: false
            ),
            0.06
        )
        XCTAssertEqual(
            TrayTabButtonStyle.backgroundOpacity(
                isSelected: false,
                isHovering: true,
                isPressed: true
            ),
            0.1
        )
        XCTAssertEqual(
            TrayTabButtonStyle.backgroundOpacity(
                isSelected: true,
                isHovering: false,
                isPressed: false
            ),
            1
        )
        XCTAssertEqual(
            TrayTabButtonStyle.backgroundOpacity(
                isSelected: true,
                isHovering: false,
                isPressed: true
            ),
            1
        )
        XCTAssertEqual(
            TrayTabButtonStyle.interactionOpacity(
                isSelected: true,
                isHovering: true,
                isPressed: false
            ),
            0.1
        )
        XCTAssertEqual(
            TrayTabButtonStyle.interactionOpacity(
                isSelected: true,
                isHovering: false,
                isPressed: true
            ),
            0.18
        )
        XCTAssertEqual(
            TrayTabButtonStyle.interactionOpacity(
                isSelected: false,
                isHovering: true,
                isPressed: true
            ),
            0
        )
    }

    func testCustomInteractionFamiliesUseSharedHoverAndPressedStyle() throws {
        let expectedStyleCounts = [
            "Views/AllToolsGridView.swift": 1,
            "Views/Components/SidebarRow.swift": 2,
            "Views/Logs/LogsWindowView.swift": 2,
            "Views/Marketplace/MarketplaceSettingsView.swift": 2,
            "Views/TextExtractor/TextExtractorView.swift": 5,
            "Views/TrayPopoverView.swift": 4,
        ]

        for (path, expectedCount) in expectedStyleCounts {
            let source = try sourceFile(path)
            XCTAssertEqual(
                source.components(separatedBy: ".buttonStyle(UtilityInteractionButtonStyle").count - 1,
                expectedCount,
                path
            )
        }
    }

    func testLongPathsUseDedicatedRowsInCompactSettings() throws {
        let marketplace = try sourceFile("Views/Marketplace/MarketplaceSettingsView.swift")
        XCTAssertTrue(marketplace.contains(
            "VStack(alignment: .leading, spacing: 2) {\n                Text(source.displayName)"
        ))
        XCTAssertTrue(marketplace.contains(
            ".lineLimit(1)\n                Text(source.url.absoluteString)"
        ))

        let cleanup = try sourceFile("Views/Rclone/CleanupRemoteSheet.swift")
        XCTAssertTrue(cleanup.contains(
            "VStack(alignment: .leading, spacing: 2) {\n                Text(\"Clean Up by Ignore Rules\")"
        ))
        XCTAssertTrue(cleanup.contains(
            ".font(.system(size: 15, weight: .semibold))\n                Text(scope)"
        ))
    }

    private func sourceFile(_ path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys")
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

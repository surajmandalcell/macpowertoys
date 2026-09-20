import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class TrayPopoverLayoutTests: XCTestCase {
    private var restoredModes: [IndividualMenuBarTool: String?] = [:]

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        for tool in IndividualMenuBarTool.allCases {
            restoredModes[tool] = defaults.string(forKey: tool.preferenceKey)
            defaults.set(MenuBarDisplayMode.combined.rawValue, forKey: tool.preferenceKey)
        }
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for (tool, value) in restoredModes {
            if let value {
                defaults.set(value, forKey: tool.preferenceKey)
            } else {
                defaults.removeObject(forKey: tool.preferenceKey)
            }
        }
    }

    func testDashboardSectionsFollowScanAndActOrder() {
        XCTAssertEqual(
            TrayPopoverLayout.dashboardSections(for: [
                "rclone", "awake", "color-picker", "text-extractor", "input-devices"
            ]),
            [.quickActions, .awake, .cloudSync, .inputDevices]
        )
        XCTAssertEqual(
            TrayPopoverLayout.dashboardSections(for: ["input-devices", "rclone"]),
            [.cloudSync, .inputDevices]
        )
        XCTAssertEqual(
            TrayPopoverLayout.dashboardSections(for: ["text-extractor"]),
            [.quickActions]
        )
        XCTAssertTrue(TrayPopoverLayout.dashboardSections(for: []).isEmpty)
    }

    func testDashboardUsesQuickControlsInsteadOfToolSettingsOrTabs() throws {
        let source = try sourceFile("Views/TrayPopoverView.swift")

        XCTAssertFalse(source.contains("ToolSettingsContent"))
        XCTAssertFalse(source.contains("TrayTabStrip"))
        XCTAssertTrue(source.contains("Picker(\"Awake duration\""))
        XCTAssertTrue(source.contains("activeJobs.prefix(3)"))
    }

    func testTrayPopoverHeightStaysWithinSeventyPercentOfTheScreen() {
        let screenHeight: CGFloat = 900
        let body = TrayPopoverLayout.maximumBodyHeight(screenHeight: screenHeight)

        XCTAssertLessThanOrEqual(
            body + TrayPopoverLayout.chromeHeight,
            screenHeight * TrayPopoverLayout.heightFraction
        )
        XCTAssertEqual(
            TrayPopoverLayout.maximumBodyHeight(screenHeight: 100),
            TrayPopoverLayout.minimumBodyHeight
        )
    }

    func testDashboardRendersInLightAndDark() throws {
        for (scheme, name) in [(ColorScheme.light, "Light"), (.dark, "Dark")] {
            let attachment = XCTAttachment(image: try renderDashboard(colorScheme: scheme))
            attachment.name = "Menu Bar Dashboard — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let manager = RcloneJobManager.shared
        let originalJobs = manager.jobs
        defer { manager.jobs = originalJobs }
        manager.jobs = [previewJob(state: .running), previewJob(state: .paused)]

        let transferAttachment = XCTAttachment(
            image: try renderDashboard(colorScheme: .dark)
        )
        transferAttachment.name = "Menu Bar Dashboard — Active and Paused Transfers"
        transferAttachment.lifetime = .keepAlways
        add(transferAttachment)
    }

    private func sourceFile(_ path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys")
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func renderDashboard(colorScheme: ColorScheme) throws -> NSImage {
        let host = NSHostingView(
            rootView: TrayPopoverView()
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, colorScheme)
        )
        host.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        host.frame = NSRect(x: 0, y: 0, width: TrayPopoverLayout.width, height: 700)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let size = host.fittingSize
        XCTAssertEqual(size.width, TrayPopoverLayout.width, accuracy: 1)
        XCTAssertGreaterThan(size.height, 200)
        XCTAssertLessThan(size.height, 700)

        host.frame.size = size
        host.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private func previewJob(state: TransferState) -> TransferJob {
        let job = TransferJob(
            operation: .copy,
            sourceFs: "/Users/example/Design Assets",
            destinationFs: "drive:Archive",
            sourceDisplay: state == .paused ? "Project Photos" : "Design Assets",
            destinationDisplay: "Drive / Archive",
            excludePatterns: [],
            maxRetries: 3
        )
        job.state = state
        job.expectedBytes = 2_000_000
        job.expectedFiles = 4
        var stats = TransferStats()
        stats.bytes = 1_200_000
        stats.totalBytes = 2_000_000
        stats.speed = 640_000
        stats.transferring = [
            FileProgress(
                name: "brand-system.sketch",
                size: 1_000_000,
                bytes: 600_000,
                percentage: 60,
                speed: 320_000,
                speedAvg: 300_000,
                eta: 2
            )
        ]
        job.stats = stats
        return job
    }
}

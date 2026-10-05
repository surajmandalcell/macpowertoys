import OnePlusUI
import AppKit
import SwiftUI
import XCTest
@testable import powertoys

final class CompactAppletRedesignTests: XCTestCase {
    func testHistoryWindowsStayWithinTheirCanvasForEmptyAndLargeHistories() {
        for count in [0, 1, 2, 5, 1000] {
            XCTAssertTrue(OnePlusWindowCanvas.colorPicker.heightRange!.contains(ColorPickerLayout.historyHeight(count: count)))
            XCTAssertTrue(OnePlusWindowCanvas.textExtractor.heightRange!.contains(TextExtractorLayout.historyHeight(count: count)))
        }
        XCTAssertEqual(ColorPickerLayout.historyHeight(count: 1000), 426)
        XCTAssertEqual(TextExtractorLayout.historyHeight(count: 1000), 446)
        XCTAssertEqual(AwakeLayout.windowWidth, 560)
        XCTAssertEqual(AwakeLayout.windowHeight, 500)
    }

    func testColorProjectsWindowGrowsUntilItsMaximumHeight() {
        XCTAssertEqual(ColorPickerLayout.projectsHeight(projectCount: 0, isCreating: false), 250)
        XCTAssertEqual(ColorPickerLayout.projectsHeight(projectCount: 1, isCreating: false), 294)
        XCTAssertEqual(ColorPickerLayout.projectsHeight(projectCount: 0, isCreating: true), 294)
        XCTAssertEqual(ColorPickerLayout.projectsHeight(projectCount: 100, isCreating: false), 460)
    }

    func testColorSettingsWindowFitsCardsAndCapsLongContent() {
        XCTAssertEqual(ColorPickerLayout.settingsHeight(contentHeight: 296), 376)
        XCTAssertEqual(ColorPickerLayout.settingsHeight(contentHeight: 0), 250)
        XCTAssertEqual(ColorPickerLayout.settingsHeight(contentHeight: 1000), 460)
        XCTAssertEqual(ColorPickerLayout.settingsHeight(contentHeight: ColorPickerLayout.settingsContentHeight), 352)
    }

    func testColorHistoryPresentationFiltersAndFormatsOffTheViewPath() throws {
        let projectID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let projectSample = ColorSample(
            id: UUID(), red: 1, green: 0, blue: 0, alpha: 1,
            createdAt: now.addingTimeInterval(-120), projectID: projectID
        )
        let unfiledSample = ColorSample(
            id: UUID(), red: 0, green: 0, blue: 1, alpha: 1,
            createdAt: now
        )

        let presentation = colorPickerPresentation(
            history: [projectSample, unfiledSample], projectID: projectID,
            search: "255, 0, 0", format: .hex, now: now
        )

        XCTAssertEqual(presentation.samples.map(\.id), [projectSample.id])
        XCTAssertEqual(presentation.samples.first?.value, "#FF0000")
        XCTAssertEqual(presentation.projectCounts[projectID], 1)
        XCTAssertEqual(presentation.unfiledCount, 1)
    }

    func testTextHistoryPresentationPreparesRowMetadata() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let extraction = TextExtraction(
            id: UUID(), text: "https://example.com/path",
            createdAt: now.addingTimeInterval(-120)
        )

        let row = try XCTUnwrap(textExtractionPresentations([extraction], now: now).first)

        XCTAssertEqual(row.id, extraction.id)
        XCTAssertEqual(row.openableURL?.absoluteString, extraction.text)
        XCTAssertFalse(row.timestamp.isEmpty)
    }

    @MainActor
    func testColorPickerTitlebarOwnsSettingsAndScrollEndsAboveTheWindowBottom() async throws {
        let suite = "color-picker-gear-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let samples = (0..<12).map { index in
            ColorSample(red: Double(index) / 12, green: 0.4, blue: 0.7, alpha: 1,
                        createdAt: Date(timeIntervalSinceReferenceDate: Double(index) * 60))
        }
        defaults.set(try JSONEncoder().encode(samples), forKey: "color-picker.history.v1")
        let service = ColorPickerService(defaults: defaults, pasteboard: NSPasteboard(name: NSPasteboard.Name(suite)))
        let directory = URL(fileURLWithPath: "/Volumes/External1TB/dev/personal/powertoys/tmp/redesign/captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for page in [ColorPickerPage.history, .projects, .settings] {
            for scheme in [ColorScheme.dark, .light] {
                let priorAppearance = NSApp.appearance
                NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                defer { NSApp.appearance = priorAppearance }
                try await Task.sleep(for: .milliseconds(300))
                let width = OnePlusWindowCanvas.colorPicker.size.width
                let host = NSHostingView(rootView: ColorHistoryView(service: service, page: page)
                    .environment(\.colorScheme, scheme))
                let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: 460),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                window.orderBack(nil)
                defer { window.close() }
                for _ in 0..<3 {
                    try await Task.sleep(for: .milliseconds(150))
                    host.layoutSubtreeIfNeeded()
                    window.setContentSize(CGSize(width: width, height: host.fittingSize.height))
                    host.layoutSubtreeIfNeeded()
                }
                let height = host.bounds.height
                for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) {
                    let end = CGRect(x: 0, y: 100_000, width: scroll.contentView.bounds.width,
                                     height: scroll.contentView.bounds.height)
                    scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(end).origin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                    if page == .history {
                        XCTAssertLessThanOrEqual(scroll.convert(scroll.bounds, to: host).maxY,
                                                 height - OnePlusMetrics.gutter + 0.5)
                    }
                }
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("applet-color-\(page.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    @MainActor
    func testAppletTitlebarGearRendersForKwakeAndTextExtractor() async throws {
        let directory = URL(fileURLWithPath: "/Volumes/External1TB/dev/personal/powertoys/tmp/redesign/captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let width = OnePlusWindowCanvas.awake.size.width
        let applets: [(String, AnyView)] = [
            ("kwake-home", AnyView(AwakeView())),
            ("kwake-settings", AnyView(AwakeView(settings: true))),
            ("text-extractor-history", AnyView(TextExtractorView())),
            ("text-extractor-settings", AnyView(TextExtractorView(page: .settings))),
        ]
        for (name, view) in applets {
            for scheme in [ColorScheme.dark, .light] {
                let priorAppearance = NSApp.appearance
                NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                defer { NSApp.appearance = priorAppearance }
                try await Task.sleep(for: .milliseconds(300))
                let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
                let size = host.fittingSize
                let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: size.width > 0 ? size.width : width,
                                                          height: size.height),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                window.orderBack(nil)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(300))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("applet-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}

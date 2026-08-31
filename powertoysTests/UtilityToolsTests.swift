import Carbon.HIToolbox
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class UtilityToolsTests: XCTestCase {
    private let alternateDockIconAssets = [
        "ClaudeHistoryLogo",
        "CloudSyncLogo",
        "LogsLogo",
        "RulerLogo",
        "AwakeLogo",
        "ColorPickerLogo",
        "TextExtractorLogo",
        "InputDevicesLogoA",
        "SystemCareLogo",
        "SystemMonitorLogo",
        "NetToysLogo"
    ]

    func testDockIconInsetsFullCanvasToOpticalBounds() throws {
        let fixture = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { bounds in
            NSColor.white.setFill()
            bounds.fill()
            return true
        }

        let image = DockIconImage.inset(fixture, appearance: NSAppearance(named: .aqua)!)

        XCTAssertEqual(try alphaBounds(of: image), NSRect(x: 58, y: 58, width: 396, height: 396))
    }

    func testEveryAlternateDockIconUsesOpticalBounds() throws {
        for assetName in alternateDockIconAssets {
            let image = try XCTUnwrap(DockIconImage.image(named: assetName))
            XCTAssertEqual(
                try alphaBounds(of: image),
                NSRect(x: 58, y: 58, width: 396, height: 396),
                assetName
            )
        }
    }

    func testEveryAlternateIconKeepsTransparentCorners() throws {
        for assetName in alternateDockIconAssets {
            let image = try XCTUnwrap(NSImage(named: assetName))
            XCTAssertTrue(
                try cornerAlphaValues(of: image).allSatisfy { $0 < 0.01 },
                assetName
            )
        }
    }

    func testEveryAlternateIconUsesSharedRoundedTileTemplate() throws {
        let assetsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys/Assets.xcassets", isDirectory: true)

        for assetName in alternateDockIconAssets {
            let iconFiles = try FileManager.default.contentsOfDirectory(
                at: assetsRoot.appendingPathComponent("\(assetName).imageset", isDirectory: true),
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "svg" }
            XCTAssertFalse(iconFiles.isEmpty, assetName)

            for iconFile in iconFiles {
                let source = String(decoding: try Data(contentsOf: iconFile), as: UTF8.self)
                XCTAssertNotNil(
                    source.range(
                        of: #"<clipPath id="tile">\s*<rect width="512" height="512" rx="112"\s*/>\s*</clipPath>"#,
                        options: .regularExpression
                    ),
                    iconFile.path
                )
                XCTAssertTrue(source.contains(#"<g clip-path="url(#tile)">"#), iconFile.path)
            }
        }
    }

    func testSharedToolIconTileRoundsEveryCorner() throws {
        let renderer = ImageRenderer(content:
            Color.white.toolIconTile(size: 32)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)

        XCTAssertTrue(try cornerAlphaValues(of: image).allSatisfy { $0 < 0.01 })
    }

    func testLogsArtworkKeepsDarkGroundInDarkAppearance() throws {
        let image = try XCTUnwrap(NSImage(named: "LogsLogo"))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 512,
            pixelsHigh: 512,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = NSSize(width: 512, height: 512)

        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
        }

        let ground = try XCTUnwrap(bitmap.colorAt(x: 256, y: 64)?.usingColorSpace(.deviceRGB))
        let luminance = 0.2126 * ground.redComponent
            + 0.7152 * ground.greenComponent
            + 0.0722 * ground.blueComponent
        XCTAssertLessThan(luminance, 0.35)
    }

    func testAppIconUsesSystemResetPath() {
        XCTAssertNil(DockIconImage.image(named: "AppIcon"))
    }

    func testDockIconMatchesActiveToolWindow() throws {
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler-window"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler-settings-window"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "preferences-window"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler-color-panel"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "awake-AppWindow-1"), "AwakeLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "color-picker"), "ColorPickerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "text-extractor"), "TextExtractorLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "input-devices"), "InputDevicesLogoA")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "system-care"), "SystemCareLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "system-monitor"), "SystemMonitorLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "nettoys"), "NetToysLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "main"), "AppIcon")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: nil), "AppIcon")
    }

    func testDockIconUpdatesWhenTheOpticalAssetOrAppearanceChanges() {
        let delegate = AppDelegate()
        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!

        XCTAssertNil(delegate.dockIconAssetToApply(for: "main", appearance: light))
        XCTAssertEqual(
            delegate.dockIconAssetToApply(for: "ruler-window", appearance: light),
            "RulerLogo"
        )
        XCTAssertNil(
            delegate.dockIconAssetToApply(for: "ruler-settings-window", appearance: light)
        )
        XCTAssertEqual(
            delegate.dockIconAssetToApply(for: "ruler-window", appearance: dark),
            "RulerLogo"
        )
        XCTAssertNil(delegate.dockIconAssetToApply(for: "ruler-window", appearance: dark))
        XCTAssertEqual(delegate.dockIconAssetToApply(for: "main", appearance: dark), "AppIcon")
        XCTAssertNil(delegate.dockIconAssetToApply(for: nil, appearance: light))
    }

    func testColorFormatting() {
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)
        XCTAssertEqual(sample.string(.hex), "#FF8000")
        XCTAssertEqual(sample.string(.rgb), "rgb(255, 128, 0)")
        XCTAssertTrue(sample.string(.swiftUI).hasPrefix("Color(red:"))
        XCTAssertTrue(sample.matches(ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0, green: 0.5, blue: 0, alpha: 1)))
    }

    func testAwakeDurationFormatting() {
        XCTAssertEqual(AwakeService.duration(65), "01:05")
        XCTAssertEqual(AwakeService.duration(3661), "1:01:01")
    }

    func testActionIDsMapToTools() {
        XCTAssertEqual(ToolActionID.rulerOpen.toolID, "ruler")
        XCTAssertEqual(ToolActionID.colorPickerCopyLast.toolID, "color-picker")
        XCTAssertEqual(ToolActionID.textExtractorCapture.toolID, "text-extractor")
    }

    func testGlobalShortcutKeysCoverAlphabetWithoutDuplicateCodes() {
        XCTAssertEqual(GlobalShortcutKey.allCases.map(\.title), Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init))
        XCTAssertEqual(Set(GlobalShortcutKey.allCases.map(\.keyCode)).count, 26)
    }

    func testFixedSizeWindowRestoreKeepsPositionNotSavedSize() {
        let saved = NSRect(x: 100, y: 300, width: 480, height: 600)
        let restored = WindowStateManager.positionOnlyFrame(saved: saved, currentSize: NSSize(width: 480, height: 320))
        XCTAssertEqual(restored.minX, 100)
        XCTAssertEqual(restored.maxY, saved.maxY)
        XCTAssertEqual(restored.size, NSSize(width: 480, height: 320))
    }

    func testDefaultGlobalShortcuts() {
        let textExtractor = GlobalShortcutAction.textExtractor.defaultShortcut
        XCTAssertEqual(textExtractor.keyCode, UInt32(kVK_ANSI_2))
        XCTAssertEqual(textExtractor.carbonModifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(textExtractor.display, "⇧⌘2")

        let colorPicker = GlobalShortcutAction.colorPicker.defaultShortcut
        XCTAssertEqual(colorPicker.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(colorPicker.carbonModifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(colorPicker.display, "⇧⌘3")
        XCTAssertTrue(colorPicker.overridesSystemScreenshotShortcut)
        XCTAssertFalse(GlobalShortcutManager.usesCarbonHotKey(for: colorPicker))
        XCTAssertTrue(GlobalShortcutManager.usesCarbonHotKey(for: textExtractor))
        XCTAssertTrue(colorPicker.matches(
            keyCode: UInt32(kVK_ANSI_3),
            flags: [.maskCommand, .maskShift]
        ))
        XCTAssertFalse(colorPicker.matches(
            keyCode: UInt32(kVK_ANSI_3),
            flags: [.maskCommand, .maskShift, .maskControl]
        ))
        XCTAssertFalse(textExtractor.overridesSystemScreenshotShortcut)
    }

    func testShortcutRecorderUsesPhysicalNumberKeyLabelWithShift() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "#",
            charactersIgnoringModifiers: "#",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_3)
        ))

        let shortcut = try XCTUnwrap(ShortcutRecorderField.shortcut(from: event))
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(shortcut.keyLabel, "3")
        XCTAssertEqual(shortcut.display, "⇧⌘3")
    }

    func testToolDetailsHideTheSegmentedPickersDuplicateLabel() throws {
        let source = try toolAboutViewSource()
        let picker = try XCTUnwrap(source.range(of: "Picker(\"Menu Bar Icon\""))
        let identifier = try XCTUnwrap(
            source.range(
                of: ".accessibilityIdentifier(\"tool.\\(tool.id).menu-bar-icon\")",
                range: picker.lowerBound..<source.endIndex
            )
        )

        XCTAssertTrue(source[picker.lowerBound..<identifier.upperBound].contains(".labelsHidden()"))
    }

    func testToolDetailsTopAlignSparseSettingsContent() throws {
        XCTAssertTrue(
            try toolAboutViewSource().contains(
                ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"
            )
        )
    }

    func testNetToysRecoverySettingsStayInteractiveWhileToolIsOff() throws {
        XCTAssertTrue(
            try toolAboutViewSource().contains(
                ".disabled(!settings.isToolEnabled(tool.id) && tool.id != \"nettoys\")"
            )
        )
    }

    func testNetToysMACAccessSurvivesAppUpdates() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys/NetToys/NetToysScanner.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("sourceCommit == expectedCommit"))
    }

    private func toolAboutViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys/Views/ToolAboutView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func alphaBounds(of image: NSImage) throws -> NSRect {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = image.size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        return maxX >= minX
            ? NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            : .zero
    }

    private func cornerAlphaValues(of image: NSImage) throws -> [CGFloat] {
        let size = 512
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

        return [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)]
            .map { bitmap.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0 }
    }
}

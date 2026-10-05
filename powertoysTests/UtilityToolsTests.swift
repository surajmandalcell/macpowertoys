import ApplicationServices
import Carbon.HIToolbox
import SwiftUI
import NetToysCore
import NetToysKit
import XCTest
@testable import powertoys

@MainActor
final class UtilityToolsTests: XCTestCase {
    private let alternateDockIconAssets = [
        "CloudSyncLogo",
        "LogsLogo",
        "RulerLogo",
        "AwakeLogo",
        "ColorPickerLogo",
        "TextExtractorLogo",
        "InputDevicesLogoA",
        "SystemCareLogo",
        "DiskExplorerLogo",
        "SystemMonitorLogo",
        "NetToysLogo",
        "MacTweaksLogo"
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
        let opticalBounds = NSRect(x: 58, y: 58, width: 396, height: 396)
        for assetName in alternateDockIconAssets {
            let image = try XCTUnwrap(DockIconImage.image(named: assetName))
            let bounds = try alphaBounds(of: image)
            XCTAssertTrue(opticalBounds.contains(bounds), assetName)
            XCTAssertGreaterThanOrEqual(bounds.width, opticalBounds.width * 0.9, assetName)
            XCTAssertGreaterThanOrEqual(bounds.height, opticalBounds.height * 0.9, assetName)
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
            ).filter { ["svg", "png"].contains($0.pathExtension) }
            XCTAssertFalse(iconFiles.isEmpty, assetName)

            for iconFile in iconFiles {
                if iconFile.pathExtension == "png" {
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: iconFile)))
                    XCTAssertEqual(bitmap.pixelsWide, 512, iconFile.path)
                    XCTAssertEqual(bitmap.pixelsHigh, 512, iconFile.path)
                    continue
                }
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

    func testEventViewerArtworkUsesCharcoalTileInBothAppearances() throws {
        let image = try XCTUnwrap(NSImage(named: "LogsLogo"))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
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

            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                defer { NSGraphicsContext.restoreGraphicsState() }
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                image.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
            }

            let ground = try XCTUnwrap(bitmap.colorAt(x: 256, y: 64)?.usingColorSpace(.deviceRGB))
            let luminance = 0.2126 * ground.redComponent
                + 0.7152 * ground.greenComponent
                + 0.0722 * ground.blueComponent
            XCTAssertLessThan(luminance, 0.3, name.rawValue)
        }
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
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "disk-explorer"), "DiskExplorerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "system-monitor"), "SystemMonitorLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "nettoys"), "NetToysLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "mac-tweaks"), "MacTweaksLogo")
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
        for seconds in [900.0, 3600.0, 5400.0, 7200.0] {
            let label = AwakeService.presetLabel(seconds)
            XCTAssertFalse(label.contains(":"), "preset chips use unit labels, not clock digits: \(label)")
            XCTAssertLessThan(label.count, AwakeService.duration(seconds).count + 3, label)
        }
        XCTAssertLessThanOrEqual(AwakeService.presetLabel(7200).count, 4)
    }

    func testAwakeTimerRunsOnlyForDeadlinesOrAttachedProcesses() {
        var configuration = AwakeConfiguration()
        XCTAssertFalse(AwakeService.requiresTimer(configuration))
        configuration.mode = .indefinite
        XCTAssertFalse(AwakeService.requiresTimer(configuration))
        configuration.mode = .timed
        XCTAssertTrue(AwakeService.requiresTimer(configuration))
        configuration.mode = .until
        XCTAssertTrue(AwakeService.requiresTimer(configuration))
        configuration.mode = .passive
        configuration.attachedProcessID = 123
        XCTAssertFalse(AwakeService.requiresTimer(configuration))
        configuration.mode = .indefinite
        XCTAssertTrue(AwakeService.requiresTimer(configuration))
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
        let portman = GlobalShortcutAction.portman.defaultShortcut
        XCTAssertEqual(portman.display, "⌥⌘P")
        XCTAssertTrue(GlobalShortcutManager.usesCarbonHotKey(for: portman))
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

    func testReservedShortcutTapRecoversFromSystemDisableEvents() throws {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: UInt16(kVK_ANSI_3),
            keyDown: true
        ))
        let callback: CFMachPortCallBack = { _, _, _, _ in }
        let eventTap = try XCTUnwrap(CFMachPortCreate(kCFAllocatorDefault, callback, nil, nil))
        defer { CFMachPortInvalidate(eventTap) }
        let disabledTypes: [CGEventType] = [.tapDisabledByTimeout, .tapDisabledByUserInput]
        var recoveredTypes: [CGEventType] = []

        for type in disabledTypes {
            _ = GlobalShortcutManager.shared.processReservedShortcutEvent(
                type: type,
                event: event,
                eventTap: eventTap
            ) { recoveredTap in
                XCTAssertTrue(recoveredTap === eventTap)
                recoveredTypes.append(type)
            }
        }

        XCTAssertEqual(recoveredTypes, disabledTypes)
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

    func testToolDetailsNameTheMenuPlacementControl() throws {
        let source = try toolAboutViewSource()
        XCTAssertTrue(source.contains("accessibilityLabel: \"Menu bar placement\""))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"tool.\\(tool.id).menu-bar-icon\")"))
    }

    func testToolDetailsTopAlignSparseSettingsContent() throws {
        XCTAssertTrue(
            try toolAboutViewSource().contains(
                ".frame(maxWidth: .infinity, alignment: .topLeading)"
            )
        )
    }

    func testDisabledToolsKeepTheirSettingsInteractive() throws {
        XCTAssertFalse(try toolAboutViewSource().contains(".disabled(!settings.isToolEnabled"))
    }

    func testEmbeddedSettingsLeavePageLayoutToTheirHost() throws {
        let source = try toolSettingsContentSource()
        for forbidden in ["OnePlusPage(", "ScrollView", ".padding(", "Spacer(", "maxHeight:"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        for content in ["RcloneSettingsView()", "AwakeSettingsView()",
                        "MacTweaksSettingsContent()", "InputDevicesSettingsContent()",
                        "SystemMonitorSettingsContent()", "SystemCareSettingsCards(mode:",
                        "MacPowerToysNetToysSettingsView()", "PortmanSettingsView()", "DiskExplorerSettingsView(showsEnableControl: false)",
                        "ColorPickerSettingsView()", "TextExtractorSettingsView()", "LogsSettingsView()"] {
            XCTAssertTrue(source.contains(content), content)
        }
    }

    func testToolSettingsRememberEachToolTabWithoutRebuildingThePage() throws {
        let source = try toolAboutViewSource()
        XCTAssertTrue(source.contains("MainToolTab.storageKey(for: toolId)"))
        XCTAssertTrue(source.contains("storedTab = MainToolTab.settings.rawValue"))
        XCTAssertNotEqual(MainToolTab.storageKey(for: "awake"), MainToolTab.storageKey(for: "rclone"))
        XCTAssertFalse(source.contains(".id(tool.id)"))
    }

    func testNetToysHistoryRetainsSSIDAcrossThePackageBoundary() throws {
        let event = NetworkTransitionEvent(networkID: "en0|192.0.2.1", ssid: "Test network",
                                           date: Date(), changes: [.internet(from: .reachable, to: .unreachable)])
        let history = NetworkHistory(events: [event])
        XCTAssertEqual(try JSONDecoder().decode(NetworkHistory.self, from: JSONEncoder().encode(history)), history)
        XCTAssertEqual(history.events.first?.ssid, "Test network")
        XCTAssertTrue(NetToysManual.sections.contains { $0.title == "Network History" })
    }

    func testNetToysMACAccessSurvivesAppUpdates() throws {
        let contract = NetToysNeighborServiceContract(host: .macPowerToys)
        XCTAssertTrue(contract.helperRequirement.contains("GF57JXJF5A"))
        XCTAssertTrue(contract.helperRequirement.contains(NetToysHostID.macPowerToys.helperIdentifier))
        XCTAssertFalse(contract.helperRequirement.contains("sourceCommit"))
        XCTAssertNotEqual(contract.machServiceName, NetToysNeighborServiceContract(host: .standalone).machServiceName)
    }

    private func toolAboutViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys/Views/ToolAboutView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func toolSettingsContentSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys/Views/Components/ToolSettingsContent.swift")
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

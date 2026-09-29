import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusUITests: XCTestCase {
    func testContentControlsKeepTheirPaintedMinimumSize() {
        let view = HStack(spacing: OnePlusMetrics.actionSpacing) {
            Button("Configure") {}
                .onePlusControl(
                    minWidth: 88,
                    minHeight: OnePlusMetrics.contentControlHeight,
                    horizontalPadding: OnePlusMetrics.contentControlHorizontalPadding
                )
            Button("Connect") {}
                .onePlusControl(
                    .primary,
                    minWidth: 88,
                    minHeight: OnePlusMetrics.contentControlHeight,
                    horizontalPadding: OnePlusMetrics.contentControlHorizontalPadding
                )
        }
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(host.fittingSize.width, 184)
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, OnePlusMetrics.contentControlHeight)
    }

    func testSharedTitlebarGeometryKeepsTheRequiredTrafficLightGap() {
        XCTAssertEqual(OnePlusMetrics.titlebarHeight, 54)
        XCTAssertEqual(OnePlusMetrics.titleLeadingInset, 84)
        XCTAssertEqual(OnePlusMetrics.fixedTitleLeadingInset, 84)
        XCTAssertEqual(OnePlusMetrics.trafficLightVerticalOffset, 11)
        XCTAssertGreaterThanOrEqual(OnePlusMetrics.titleLeadingInset - 70, 12)
        XCTAssertGreaterThanOrEqual(OnePlusMetrics.fixedTitleLeadingInset - 48, 12)
    }

    func testSearchTextCellCentersItsSingleDisplayAndEditingRect() {
        let cell = OnePlusCenteredTextFieldCell(textCell: "Search name, path, or PID")
        cell.font = .systemFont(ofSize: 10.5)
        let bounds = NSRect(x: 0, y: 0, width: 240, height: 18)
        let textRect = cell.drawingRect(forBounds: bounds)

        XCTAssertEqual(textRect.midY, bounds.midY, accuracy: 0.5)
        XCTAssertGreaterThan(textRect.minY, bounds.minY)
        XCTAssertLessThan(textRect.maxY, bounds.maxY)
    }

    func testDitherTextureLoadsItsPackagedImage() {
        XCTAssertNotNil(OnePlusDitherTexture.resourceImage)
        XCTAssertEqual(OnePlusDitherTexture.resourceImage?.size, NSSize(width: 240, height: 150))
    }

    func testFixedWindowChromeReappliesSizeAndStyle() {
        let expectedSize = NSSize(width: 920, height: 680)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 700, height: 500)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: OnePlusFixedWindowChrome(contentSize: expectedSize))
        window.contentView?.layoutSubtreeIfNeeded()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))

        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.contentView?.bounds.size, expectedSize)
        XCTAssertEqual(window.frame.size, expectedSize)
        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, NSColor(OnePlusTheme.window))
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)?.isHidden))
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)?.isEnabled))
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try! XCTUnwrap(window.standardWindowButton(type))
            XCTAssertEqual(window.frame.height - button.convert(button.bounds, to: nil).midY, 27, accuracy: 0.5)
        }
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.appearance = NSAppearance(named: .aqua)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)?.isHidden))
    }

    func testOverlayScrollerKeepsNativeBehaviorAndThinGeometry() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 100))
        scroll.hasVerticalScroller = true
        scroll.configureOnePlusScrollIndicators()
        XCTAssertTrue(scroll.verticalScroller is OnePlusOverlayScroller)
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertEqual(OnePlusOverlayScroller.knobThickness(increasedContrast: false), 4)
        XCTAssertEqual(OnePlusOverlayScroller.knobThickness(increasedContrast: true), 6)
        let scroller = scroll.verticalScroller
        scroll.configureOnePlusScrollIndicators()
        XCTAssertTrue(scroller === scroll.verticalScroller)
        scroll.scrollerStyle = .legacy
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(scroll.scrollerStyle, .overlay, "System or SwiftUI style changes must not consume a gutter.")
        XCTAssertEqual(scroll.contentSize.width, 240)
    }

    func testAllDynamicTokensResolveToTheContractInBothAppearances() throws {
        let tokens: [(Color, UInt32, UInt32)] = [
            (.init(OnePlusColor.window), 0x161616, 0xF5F5F5),
            (OnePlusColor.sidebar, 0x1D1D1D, 0xE7E7E7), (OnePlusColor.panel, 0x202020, 0xFAFAFA),
            (OnePlusColor.panelHover, 0x262626, 0xFFFFFF), (OnePlusColor.raised, 0x292929, 0xFFFFFF),
            (OnePlusColor.raisedHover, 0x303030, 0xF0F0F0), (OnePlusColor.pressed, 0x252525, 0xE4E4E4),
            (OnePlusColor.field, 0x252525, 0xF2F2F2), (OnePlusColor.fieldFocus, 0x2B2B2B, 0xEAEAEA),
            (OnePlusColor.track, 0x181818, 0xE4E4E4), (OnePlusColor.selection, 0x343434, 0xD4D4D4),
            (OnePlusColor.selectedControl, 0x424242, 0xFFFFFF), (OnePlusColor.line, 0x343434, 0xD1D1D1),
            (OnePlusColor.lineSoft, 0x2B2B2B, 0xE1E1E1), (OnePlusColor.ink, 0xEDEDED, 0x242424),
            (OnePlusColor.secondary, 0xA3A3A3, 0x656565), (OnePlusColor.muted, 0x8A8A8A, 0x707070),
            (OnePlusColor.controlInk, 0xDEDEDE, 0x343434), (OnePlusColor.accent, 0xEE5B50, 0xD94F45),
            (OnePlusColor.primaryFill, 0xDDDDDD, 0x383838), (OnePlusColor.primaryInk, 0x252525, 0xFFFFFF),
            (OnePlusColor.ok, 0x7FA889, 0x3F7A4E), (OnePlusColor.warn, 0xF29A68, 0xC06A32),
            (OnePlusColor.danger, 0xE99B91, 0xB8463B), (OnePlusColor.dangerFill, 0x382624, 0xFBE9E7),
            (OnePlusColor.dangerLine, 0x6D4541, 0xE3B3AD)
        ]
        for (name, dark) in [(NSAppearance.Name.darkAqua, true), (.aqua, false)] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                for (color, darkHex, lightHex) in tokens {
                    let rgb = NSColor(color).usingColorSpace(.sRGB)!
                    let hex = dark ? darkHex : lightHex
                    XCTAssertEqual(rgb.redComponent, CGFloat((hex >> 16) & 255) / 255, accuracy: 0.001)
                    XCTAssertEqual(rgb.greenComponent, CGFloat((hex >> 8) & 255) / 255, accuracy: 0.001)
                    XCTAssertEqual(rgb.blueComponent, CGFloat(hex & 255) / 255, accuracy: 0.001)
                }
            }
        }
    }

    func testCenterlineAndWindowCanvases() {
        XCTAssertEqual(OnePlusMetrics.top(of: 14), 20)
        XCTAssertEqual(OnePlusMetrics.top(of: 14, centerline: 22), 15)
        XCTAssertEqual(OnePlusMetrics.titleStart(afterZoom: 73), 87)
        XCTAssertEqual(OnePlusWindowCanvas.main.size, CGSize(width: 1240, height: 840))
        XCTAssertEqual(OnePlusWindowCanvas.systemMonitor.density, .compact)
        XCTAssertEqual(OnePlusWindowCanvas.colorPicker.heightRange, 250...460)
        XCTAssertEqual(OnePlusWindowCanvas.textExtractor.size.width, 480)
    }

    func testDotGlyphCoverageAndPathCache() {
        let titles = ["Overview", "Processes", "CPU", "GPU", "Memory", "Network", "Disk", "Battery", "Sensors", "Remote stats", "System Report", "About", "Settings"]
        for title in titles {
            XCTAssertTrue(title.uppercased().allSatisfy { OnePlusDotGlyphs.glyphs[$0] != nil })
            let drawing = OnePlusDotGlyphs.drawing(title, height: 20, scale: 2)
            XCTAssertFalse(drawing.path.isEmpty)
            XCTAssertTrue(drawing === OnePlusDotGlyphs.drawing(title, height: 20, scale: 2))
        }
        for rows in OnePlusDotGlyphs.glyphs.values {
            XCTAssertEqual(rows.count, 7)
            XCTAssertTrue(rows.allSatisfy { $0.count == rows[0].count })
        }
        XCTAssertEqual(OnePlusDotGlyphs.drawing("I", height: 7, scale: 1).width, 3)
        XCTAssertEqual(OnePlusDotGlyphs.drawing("", height: 7, scale: 1).width, 0)
    }

    func testSegmentSelectionNeverLeavesTheAvailableOptions() {
        let options = ["Default (Off)", "On", "Off"]
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: options, current: "On", direction: -1), "Default (Off)")
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: options, current: "On", direction: 1), "Off")
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: options, current: "Off", direction: 1), "Off")
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: options, current: "Default (Off)", direction: -1), "Default (Off)")
        XCTAssertNil(OnePlusSegmented<String>.nextSelection(in: [], current: "On", direction: 1))
    }

    func testSegmentsKeepTheirFullLabelWidths() {
        for labels in [["Default (Off)", "On", "Off"], ["None", "Combined", "Separate"]] {
            for density in OnePlusDensity.allCases {
                let host = NSHostingView(rootView: OnePlusSegmented(
                    choices: labels.map { ($0, $0) }, selection: .constant(labels[0]))
                    .onePlusDensity(density))
                let font = NSFont.systemFont(ofSize: OnePlusTextRole.control.size(for: density))
                let required = labels.reduce(CGFloat(8)) { $0 + ($1 as NSString).size(withAttributes: [.font: font]).width + 8 }
                XCTAssertGreaterThanOrEqual(host.fittingSize.width, floor(required))
                XCTAssertLessThanOrEqual(host.fittingSize.width, OnePlusMetrics.wideControlColumn)
                XCTAssertEqual(host.fittingSize.height, density.controlHeight)
                print("Segment width", labels.joined(separator: " / "), density, host.fittingSize.width)
            }
        }
    }

    func testSettingRowsIncludeTheirSeparatorInThePitch() {
        for separator in [true, false] {
            let host = NSHostingView(rootView: OnePlusCard {
                OnePlusSettingRow("First", separator: separator) { Text("Value") }
                OnePlusSettingRow("Second", separator: separator) { Text("Value") }
                OnePlusSettingRow("Third", caption: "Details", separator: separator) { Text("Value") }
            }.frame(width: 500))
            XCTAssertEqual(host.fittingSize.height, 44 + 44 + 56)
        }
    }

    func testDefaultButtonHeightFollowsDensityAndExplicitSizeWins() {
        for density in OnePlusDensity.allCases {
            for size: OnePlusButtonStyle.Size? in [nil, .regular, .small] {
                let host = NSHostingView(rootView: Button("Action") {}
                    .buttonStyle(OnePlusButtonStyle(size: size)).onePlusDensity(density))
                XCTAssertEqual(host.fittingSize.height, size.map { $0 == .small ? 24 : 28 } ?? density.controlHeight)
            }
        }
    }

    func testFloatingGearReservesItsBodyArea() {
        let host = NSHostingView(rootView: Color.clear.frame(width: 300, height: 100)
            .onePlusFloatingSettings(isActive: false) {})
        XCTAssertEqual(host.fittingSize.height, 152)
        XCTAssertEqual(host.fittingSize.width, 300)
    }

    func testHealthyStatusUsesNeutralInkUnlessSuccessIsExplicit() {
        XCTAssertEqual(OnePlusStatus("Connected").state, .neutral)
        XCTAssertEqual(OnePlusStatus("Healthy").color, OnePlusColor.secondary)
        XCTAssertEqual(OnePlusStatus("Online", state: .online).color, OnePlusColor.secondary)
        XCTAssertEqual(OnePlusStatus("Complete", state: .success).color, OnePlusColor.ok)
    }

    func testMenuGridMatchesMeasuredReference() {
        XCTAssertEqual(OnePlusMenuMetrics.columnWidth(), 109.333333333, accuracy: 0.000001)
        XCTAssertEqual(OnePlusMenuMetrics.columnWidth(span: 2), 223.666666667, accuracy: 0.000001)
        XCTAssertEqual(OnePlusMenuMetrics.columnWidth(span: 3), 338)
        XCTAssertEqual(OnePlusMenuMetrics.columnWidth(span: 0), OnePlusMenuMetrics.columnWidth())
    }

    func testMenuPanelMeasuresShortContentWithoutCollapsingItsBody() {
        let host = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: 300,
            tabs: OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")],
                                      selection: .constant("home")),
            actions: OnePlusMenuOpenApp {},
            content: { Color.clear.frame(height: 100) }
        ).environment(\.onePlusIsVisible, true))
        host.frame.size = NSSize(width: 356, height: 300)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 356, accuracy: 0.5)
        XCTAssertEqual(host.fittingSize.height, OnePlusMenuMetrics.topBar + 100 + 3 + 8, accuracy: 0.5)
    }

    func testAllFourTextureResourcesKeepTheirPixelDimensions() throws {
        for (asset, size) in [(OnePlusTextureAsset.grain, CGSize(width: 240, height: 150)),
                              (.ribbon, CGSize(width: 700, height: 220)),
                              (.diskDither, CGSize(width: 384, height: 384)),
                              (.partitionBand, CGSize(width: 768, height: 128))] {
            let image = try XCTUnwrap(asset.image)
            let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertEqual(bitmap.width, Int(size.width))
            XCTAssertEqual(bitmap.height, Int(size.height))
        }
    }

    func testChartCachesPathsAndHandlesMissingAndOutOfRangeSamples() {
        let paths = OnePlusChartPaths.cached(values: [-20, 50, 140], range: 0...100)
        XCTAssertTrue(paths === OnePlusChartPaths.cached(values: [-20, 50, 140], range: 0...100))
        XCTAssertEqual(paths.line.boundingRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertTrue(OnePlusChartPaths.cached(values: [.nan, .infinity], range: 0...100).line.isEmpty)
        XCTAssertFalse(OnePlusChartPaths.cached(values: [50], range: 0...100).line.isEmpty)
    }
}

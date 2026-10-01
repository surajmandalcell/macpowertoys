import AppKit
import OnePlusUI
import XCTest
@testable import powertoys

@MainActor
final class ToolGlyphTests: XCTestCase {
    func testToolGlyphsAndStatusImagesShareTheApprovedGeometry() throws {
        let tools = ToolRegistry.builtInTools
        XCTAssertEqual(tools.count, 14)
        XCTAssertEqual(Set(tools.map(\.icon)).count, tools.count)
        XCTAssertEqual(Set(tools.map(\.id)), Set(ToolGlyph.allCases.map(\.rawValue)))
        for tool in tools {
            let glyph = try XCTUnwrap(ToolGlyph(rawValue: tool.id))
            XCTAssertEqual(tool.icon, glyph.symbol)
            XCTAssertEqual(tool.iconRotation, tool.id == "ruler" ? -45 : 0)
        }
        for tab in TrayTab.allCases where tab != .home {
            XCTAssertEqual(tab.symbol, try XCTUnwrap(ToolGlyph(rawValue: tab.rawValue)).symbol)
        }
        for tool in IndividualMenuBarTool.allCases {
            XCTAssertEqual(tool.symbol, try XCTUnwrap(ToolGlyph(rawValue: tool.rawValue)).symbol)
        }
        let images = try ToolGlyph.allCases.map { try XCTUnwrap(StatusItemIcon.symbol($0.symbol)) }
            + SystemMonitorMenuMetric.allCases.flatMap { $0.symbols }.map { try XCTUnwrap(StatusItemIcon.symbol($0)) }
            + [StatusItemIcon.main]
        for image in images {
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 14, height: 14))
            for scale in [CGFloat(1), 2, 4] {
                let bounds = try inkBounds(image, scale: scale)
                // Allow one antialiased edge pixel on each side.
                XCTAssertEqual(max(bounds.width, bounds.height), 11.2, accuracy: max(0.5, 2 / scale))
                XCTAssertEqual(bounds.midX, 7, accuracy: 0.5)
                XCTAssertEqual(bounds.midY, 7, accuracy: 0.5)
            }
        }
        XCTAssertTrue(StatusItemIcon.symbol("eye") === StatusItemIcon.symbol("eye"))
        XCTAssertNil(StatusItemIcon.symbol("not-a-symbol"))
    }

    func testSoleMetricUsesTaskManagerWithoutChangingSavedMetricGlyphs() {
        for metric in SystemMonitorMenuMetric.allCases {
            for symbol in metric.symbols + ["not-a-symbol"] {
                let item = SystemMonitorMenuItemConfiguration(metric: metric, symbol: symbol)
                XCTAssertEqual(SystemMonitorMenuRenderer.symbol(for: item, itemCount: 1), "waveform.path.ecg.rectangle")
                XCTAssertEqual(SystemMonitorMenuRenderer.symbol(for: item, itemCount: 2),
                               metric.symbols.contains(symbol) ? symbol : metric.symbol)
                XCTAssertEqual(item.symbol, symbol)
            }
        }
    }

    func testPortmanKeepsTheOriginalStatusAsset() throws {
        let image = try XCTUnwrap(StatusItemIcon.symbol(ToolGlyph.portman.symbol))
        let original = try XCTUnwrap(NSImage(named: "PortmanStatusGlyph")?.copy() as? NSImage)
        original.size = NSSize(width: 14, height: 14)
        original.isTemplate = true
        for scale in [CGFloat(1), 2, 4] {
            XCTAssertEqual(try raster(image, scale: scale).tiffRepresentation,
                           try raster(original, scale: scale).tiffRepresentation)
        }
    }

    func testAssetGlyphsReuseOneRasterInsteadOfSVGDrawings() throws {
        for glyph in ToolGlyph.allCases where glyph.isAsset {
            let first = try XCTUnwrap(glyph.assetNSImage)
            XCTAssertTrue(first.isTemplate)
            XCTAssertEqual(first.size, NSSize(width: 32, height: 32))
            XCTAssertTrue(first.representations.allSatisfy { $0.pixelsWide >= 128 && $0.pixelsHigh >= 128 })
            for _ in 0..<100 { XCTAssertTrue(glyph.assetNSImage === first) }
            let bitmap = try XCTUnwrap(first.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertGreaterThanOrEqual(bitmap.width, 128)
            XCTAssertGreaterThanOrEqual(bitmap.height, 128)
        }
        XCTAssertNil(ToolGlyph.awake.assetNSImage)
    }

    private func raster(_ image: NSImage, scale: CGFloat) throws -> NSBitmapImageRep {
        let side = Int(14 * scale)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func inkBounds(_ image: NSImage, scale: CGFloat) throws -> NSRect {
        let bitmap = try raster(image, scale: scale)
        let side = bitmap.pixelsWide
        var bounds = NSRect.null
        for y in 0..<side {
            for x in 0..<side where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                bounds = bounds.union(NSRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: 1 / scale, height: 1 / scale))
            }
        }
        XCTAssertFalse(bounds.isNull)
        return bounds
    }
}

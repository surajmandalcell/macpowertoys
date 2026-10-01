import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusProcessIconTests: XCTestCase {
    func testAppTerminalAndEmptySlotsRenderWithoutMovingNames() throws {
        let icon = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: OnePlusNativeTable(
                columns: [.init("Process", width: 200)],
                rows: [
                    .init(id: "app", cells: ["App"], symbol: "", image: icon),
                    .init(id: "cli", cells: ["Command"], symbol: "terminal"),
                    .init(id: "unknown", cells: ["Unknown"], symbol: ""),
                ], selection: .constant([]), sort: { _, _ in }, actions: { _ in [] }
            ).onePlusDensity(.compact))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 260, height: 180),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let table = try XCTUnwrap(findTable(in: host))
            var origins: [CGFloat] = []
            for index in 0..<3 {
                let cell = try XCTUnwrap(table.view(atColumn: 0, row: index, makeIfNecessary: true) as? NSTableCellView)
                cell.layoutSubtreeIfNeeded()
                let imageView = try XCTUnwrap(cell.imageView)
                origins.append(try XCTUnwrap(cell.textField).frame.minX)
                XCTAssertEqual(imageView.frame.width, 15)
                if index == 0 {
                    XCTAssertTrue(imageView.image === icon)
                    XCTAssertNil(imageView.contentTintColor)
                    let bitmap = try XCTUnwrap(imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds))
                    imageView.cacheDisplay(in: imageView.bounds, to: bitmap)
                    let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                    XCTAssertGreaterThan(color.redComponent, color.greenComponent)
                    XCTAssertGreaterThan(color.redComponent, color.blueComponent)
                } else if index == 1 {
                    XCTAssertNotNil(imageView.image)
                } else {
                    XCTAssertNil(imageView.image)
                }
            }
            XCTAssertEqual(Set(origins).count, 1)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
        }
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
    }
}

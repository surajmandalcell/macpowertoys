import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusControlGeometryTests: XCTestCase {
    func testEditorBezelPaintsAboveTheNativeClipInBothAppearances() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let host = NSHostingView(rootView: OnePlusTextEditor("Rules", text: .constant("*.tmp")))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 300, height: 120),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            func find(_ view: NSView) -> OnePlusEditorBezel? {
                if let bezel = view as? OnePlusEditorBezel { return bezel }
                return view.subviews.lazy.compactMap(find).first
            }
            let bezel = try XCTUnwrap(find(host))
            XCTAssertTrue(bezel.superview?.subviews.last === bezel)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let edge = try XCTUnwrap(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh / 2))
            let fill = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
            XCTAssertGreaterThan(abs(edge.redComponent - fill.redComponent), 0.02)
            XCTAssertNil(bezel.hitTest(.zero))
        }
    }
    func testDeclaredSegmentWidthPaintsTheCompleteTrackInEveryDensityAndState() throws {
        for density in OnePlusDensity.allCases {
            for width in [CGFloat(160), 180] {
                for enabled in [false, true] {
                    let host = NSHostingView(rootView: OnePlusSegmented(
                        choices: [("default", "Default (Off)"), ("on", "On"), ("off", "Off")],
                        selection: .constant("default"), width: width
                    ).disabled(!enabled).onePlusDensity(density).background(OnePlusColor.panel))
                    host.appearance = NSAppearance(named: .darkAqua)
                    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: density.controlHeight),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.contentView = host
                    host.frame = CGRect(x: 0, y: 0, width: width, height: density.controlHeight)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(host.fittingSize.width, width, accuracy: 0.5)
                    XCTAssertEqual(host.fittingSize.height, density.controlHeight, accuracy: 0.5)
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let scale = CGFloat(bitmap.pixelsWide) / width
                    let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
                    for x in [0, bitmap.pixelsWide - 1] {
                        let edge = try XCTUnwrap(bitmap.colorAt(x: x, y: Int(density.controlHeight / 2 * scale)))
                        XCTAssertGreaterThan(edge.redComponent, corner.redComponent, "The line must enclose the full declared width")
                    }
                }
            }
        }
    }
}

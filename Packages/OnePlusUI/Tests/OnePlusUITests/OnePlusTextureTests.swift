import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusTextureTests: XCTestCase {
    func testSharedCardGrainDoesNotChangeOpaqueContentPixels() throws {
        let mark = Color(.sRGB, red: 0.1, green: 0.8, blue: 0.2)
        let surfaces: [(Bool) -> AnyView] = [
            { AnyView(OnePlusCard(textured: $0) { mark.frame(height: 70) }) },
            { AnyView(OnePlusMenuCard(textured: $0, padded: false) { mark.frame(height: 70) }) },
            { AnyView(OnePlusMenuTile(height: 70, textured: $0) { mark }) }
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            for surface in surfaces {
                var images: [NSBitmapImageRep] = []
                for textured in [false, true] {
                    let host = NSHostingView(rootView: surface(textured))
                    host.appearance = NSAppearance(named: name)
                    host.frame = .init(x: 0, y: 0, width: 160, height: 70)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    images.append(bitmap)
                }
                var checked = 0
                for y in 0..<images[0].pixelsHigh {
                    for x in 0..<images[0].pixelsWide {
                        let plain = try XCTUnwrap(images[0].colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        guard plain.greenComponent > 0.7, plain.redComponent < 0.2, plain.blueComponent < 0.3 else { continue }
                        let grain = try XCTUnwrap(images[1].colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        XCTAssertEqual(plain.redComponent, grain.redComponent, accuracy: 0.005)
                        XCTAssertEqual(plain.greenComponent, grain.greenComponent, accuracy: 0.005)
                        checked += 1
                    }
                }
                XCTAssertGreaterThan(checked, 100)
            }
            // Metric tiles always carry grain; opaque chart content must still keep its original ink.
            let host = NSHostingView(rootView: OnePlusMetricTile("Metric", systemImage: "cpu", value: "24") {
                mark.frame(height: 40)
            })
            host.appearance = NSAppearance(named: name)
            host.frame = .init(x: 0, y: 0, width: 300, height: 110)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let chart = try XCTUnwrap(bitmap.colorAt(x: Int(230 * scale), y: Int(75 * scale))?.usingColorSpace(.sRGB))
            XCTAssertEqual(chart.redComponent, 0.1, accuracy: 0.01)
            XCTAssertEqual(chart.greenComponent, 0.8, accuracy: 0.01)
        }
    }
}

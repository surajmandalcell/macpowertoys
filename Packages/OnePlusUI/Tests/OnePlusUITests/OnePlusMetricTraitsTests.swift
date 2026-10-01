import AppKit
import CoreText
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusMetricTraitsTests: XCTestCase {
    func testMetricLineAndPaintMatchAcrossDensitiesAndAppearances() throws {
        XCTAssertEqual(OnePlusMetricTypography.nativeFont.pointSize, 27)
        let variations = try XCTUnwrap(CTFontCopyVariation(OnePlusMetricTypography.nativeFont as CTFont) as? [NSNumber: NSNumber])
        XCTAssertEqual(variations[NSNumber(value: 0x77676874)]?.doubleValue, 550)
        XCTAssertEqual(OnePlusMetricTypography.lineHeight, 30.24)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            var images: [NSBitmapImageRep] = []
            for density in OnePlusDensity.allCases {
                XCTAssertEqual(OnePlusTextRole.metric.size(for: density), 27)
                let value = Text("686").onePlusText(.metric).onePlusDensity(density)
                XCTAssertEqual(NSHostingView(rootView: value).fittingSize.height, ceil(30.24))
                images.append(try render(value.frame(width: 120, height: 40).background(OnePlusColor.panel),
                                         size: .init(width: 120, height: 40), appearance: appearance))
            }
            XCTAssertEqual(images[0].representation(using: .png, properties: [:]),
                           images[1].representation(using: .png, properties: [:]))
            XCTAssertNotNil(images[0].representation(using: .png, properties: [:]))
        }
    }

    func testMetricCaptionInkIsQuietAndReadable() throws {
        for (name, hex) in [(NSAppearance.Name.darkAqua, UInt32(0xA0A0A0)), (.aqua, 0x5B5B5B)] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let ink = NSColor(OnePlusTextRole.metricCaption.color).usingColorSpace(.sRGB)!
                let primary = NSColor(OnePlusColor.ink).usingColorSpace(.sRGB)!
                XCTAssertEqual(ink.redComponent, CGFloat(hex & 255) / 255, accuracy: 0.001)
                XCTAssertEqual(ink.redComponent, ink.greenComponent, accuracy: 0.001)
                XCTAssertEqual(ink.greenComponent, ink.blueComponent, accuracy: 0.001)
                for surface in [OnePlusColor.panel, OnePlusColor.panelHover, OnePlusColor.raised, OnePlusColor.selection] {
                    let background = NSColor(surface).usingColorSpace(.sRGB)!
                    XCTAssertGreaterThanOrEqual(contrast(ink, background), 4.5)
                    XCTAssertGreaterThan(contrast(primary, background), contrast(ink, background))
                }
            }
        }
    }

    func testWaveExtentAndContentLayeringInBothAppearances() throws {
        XCTAssertEqual(OnePlusMetricTexture.size, CGSize(width: 180, height: 110))
        XCTAssertEqual(OnePlusMetricTexture.opacity, 0.07)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let wave = try render(OnePlusColor.panel.overlay { OnePlusMetricTexture() },
                                  size: .init(width: 260, height: 140), appearance: appearance)
            let plain = try render(OnePlusColor.panel, size: .init(width: 260, height: 140), appearance: appearance)
            let scale = CGFloat(wave.pixelsWide) / 260
            var changes = 0
            for y in 0..<wave.pixelsHigh {
                for x in 0..<wave.pixelsWide {
                    let textured = try XCTUnwrap(wave.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let base = try XCTUnwrap(plain.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let delta = abs(textured.redComponent - base.redComponent)
                    XCTAssertEqual(textured.redComponent, textured.greenComponent, accuracy: 0.005)
                    XCTAssertEqual(textured.greenComponent, textured.blueComponent, accuracy: 0.005)
                    XCTAssertLessThanOrEqual(delta, 0.075)
                    if CGFloat(x) < 80 * scale || CGFloat(y) >= 110 * scale {
                        XCTAssertLessThan(delta, 0.005)
                    } else if delta > 0.005 { changes += 1 }
                }
            }
            XCTAssertGreaterThan(changes, 30, "The ribbon must paint inside its 180 x 110 pt corner.")
            let mark = Color(.sRGB, red: 0.1, green: 0.8, blue: 0.2)
            let surfaces: [(Bool) -> AnyView] = [
                { AnyView(OnePlusMenuTile(height: 110, textured: $0) { mark }) },
                { AnyView(OnePlusCard(textured: $0) { mark.frame(height: 110) }) },
                { AnyView(OnePlusMenuCard(textured: $0, padded: false) { mark.frame(height: 110) }) }
            ]
            for surface in surfaces {
                let image = try render(surface(true), size: .init(width: 300, height: 110), appearance: appearance)
                let reference = try render(surface(false), size: .init(width: 300, height: 110), appearance: appearance)
                var opaquePixels = 0
                for y in 0..<image.pixelsHigh {
                    for x in 0..<image.pixelsWide {
                        let plain = try XCTUnwrap(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        guard plain.greenComponent > 0.7, plain.redComponent < 0.2 else { continue }
                        let pixel = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        XCTAssertEqual(pixel.redComponent, plain.redComponent, accuracy: 0.005)
                        XCTAssertEqual(pixel.greenComponent, plain.greenComponent, accuracy: 0.005)
                        opaquePixels += 1
                    }
                }
                XCTAssertGreaterThan(opaquePixels, 100)
            }
        }
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        }
        let first = luminance(a), second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
        host.appearance = NSAppearance(named: appearance)
        host.frame = .init(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}

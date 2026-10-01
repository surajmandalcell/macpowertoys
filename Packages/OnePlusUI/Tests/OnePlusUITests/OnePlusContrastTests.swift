import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusContrastTests: XCTestCase {
    func testSemanticTextAndHighContrastOutlinesOnPermittedSurfacesAndGrainExtremes() throws {
        let image = try XCTUnwrap(OnePlusTextureAsset.grain.image)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        var extremes = [CGFloat(1), CGFloat(0)]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let value = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent
                extremes[0] = min(extremes[0], value); extremes[1] = max(extremes[1], value)
            }
        }
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                var minimum = Double.infinity
                for ink in [OnePlusColor.muted, OnePlusColor.warn, OnePlusColor.danger] {
                    for fill in [OnePlusColor.window, OnePlusColor.sidebar, OnePlusColor.panel, OnePlusColor.panelHover, OnePlusColor.raised, OnePlusColor.raisedHover, OnePlusColor.pressed, OnePlusColor.field, OnePlusColor.fieldFocus, OnePlusColor.selection, OnePlusColor.selectionInactive, OnePlusColor.dangerFill] {
                        let base = NSColor(fill).usingColorSpace(.sRGB)!
                        for strength in [CGFloat(0), 0.11, 0.14] {
                            for grain in extremes {
                                let background = NSColor(srgbRed: base.redComponent * (1 - strength) + grain * strength,
                                                         green: base.greenComponent * (1 - strength) + grain * strength,
                                                         blue: base.blueComponent * (1 - strength) + grain * strength, alpha: 1)
                                let ratio = contrast(NSColor(ink), background)
                                minimum = min(minimum, ratio)
                                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name), \(ink), \(fill), grain \(strength)")
                            }
                        }
                    }
                }
                print("Semantic text minimum \(name): \(minimum)")
                if name == .accessibilityHighContrastAqua || name == .accessibilityHighContrastDarkAqua {
                    // This OS normalizes requested contrast appearances while the preference is off.
                    // Exercise the same resolver with the native preference input on.
                    let boundary = OnePlusColor.resolve(appearance: appearance, increasedContrast: true,
                        dark: 0x343434, light: 0xD1D1D1, highContrastDark: 0xA0A0A0, highContrastLight: 0x707070)
                    let highInk = OnePlusColor.resolve(appearance: appearance, increasedContrast: true,
                        dark: 0xBCBCBC, light: 0x565656, highContrastDark: 0xDADADA, highContrastLight: 0x444444)
                    XCTAssertNotEqual(boundary, NSColor(OnePlusColor.line))
                    for fill in [OnePlusColor.window, OnePlusColor.panel, OnePlusColor.raised, OnePlusColor.field, OnePlusColor.fieldFocus] {
                        XCTAssertGreaterThanOrEqual(contrast(boundary, NSColor(fill)), 3)
                        XCTAssertGreaterThanOrEqual(contrast(highInk, NSColor(fill)), 4.5)
                    }
                }
            }
        }
    }

    private func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            let rgb = color.usingColorSpace(.sRGB)!
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

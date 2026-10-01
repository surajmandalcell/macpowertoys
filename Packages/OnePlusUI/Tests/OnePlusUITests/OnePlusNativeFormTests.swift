import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor final class OnePlusNativeFormTests: XCTestCase {
    func testNativeSwitchPaintUsesTheSharedTrackAndThumbBounds() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for state in [NSControl.StateValue.off, .on] {
                let control = OnePlusNativeSwitchButton(frame: .init(x: 0, y: 0, width: 60, height: 28))
                control.title = ""; control.state = state
                control.appearance = NSAppearance(named: appearance)
                let bitmap = try XCTUnwrap(control.bitmapImageRepForCachingDisplay(in: control.bounds))
                control.cacheDisplay(in: control.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / control.bounds.width
                var track = CGRect.null, thumb = CGRect.null
                var thumbColor = NSColor.clear
                control.effectiveAppearance.performAsCurrentDrawingAppearance {
                    thumbColor = NSColor(state == .on ? OnePlusColor.primaryInk : OnePlusColor.secondary).usingColorSpace(.sRGB)!
                }
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        let rect = CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: 1 / scale, height: 1 / scale)
                        if pixel.alphaComponent > 0.5 { track = track.union(rect) }
                        if pixel.alphaComponent > 0.9, abs(pixel.redComponent - thumbColor.redComponent) < 0.01 {
                            thumb = thumb.union(rect)
                        }
                    }
                }
                XCTAssertEqual(track.width, 29, accuracy: 0.5)
                // At 1x the 17pt track straddles two half-pixel rows; the solid thumb core excludes antialiasing.
                XCTAssertEqual(track.height, 18, accuracy: 0.5)
                XCTAssertEqual(thumb.width, 9, accuracy: 0.5)
                XCTAssertEqual(thumb.height, 10, accuracy: 0.5)
            }
        }
    }

    func testStepperBridgesKeepTheirIntrinsicPaintInsideBothHostHeights() throws {
        func stepper(in view: NSView) -> NSStepper? {
            if let value = view as? NSStepper { return value }
            return view.subviews.lazy.compactMap { stepper(in: $0) }.first
        }
        for height in [CGFloat(24), 28] {
            let native = OnePlusNativeStepperField(frame: .init(x: 0, y: 0, width: 100, height: height))
            native.awakeFromNib(); native.layout()
            let host = NSHostingView(rootView: OnePlusStepperField("Limit", value: .constant(4), in: 0...10)
                .environment(\.onePlusControlHeight, height))
            host.frame = .init(x: 0, y: 0, width: 100, height: height)
            host.layoutSubtreeIfNeeded()
            let first = try XCTUnwrap(stepper(in: native)), second = try XCTUnwrap(stepper(in: host))
            print("Stepper host \(height): native \(first.controlSize) \(first.frame), SwiftUI \(second.controlSize) \(second.frame), intrinsic \(second.intrinsicContentSize)")
            XCTAssertEqual(first.controlSize, second.controlSize)
            XCTAssertEqual(first.frame.size, second.frame.size)
            for control in [first, second] {
                XCTAssertGreaterThanOrEqual(control.frame.minY, 0)
                XCTAssertLessThanOrEqual(control.frame.maxY, height)
            }
        }
    }

    func testNumberStepperUsesCurrentFieldValueAndFormatterLimits() throws {
        let field = OnePlusNativeStepperField(frame: NSRect(x: 0, y: 0, width: 72, height: 24))
        field.awakeFromNib()
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 4000
        field.formatter = formatter
        field.stringValue = "260"
        field.layout()
        let stepper = try XCTUnwrap(field.subviews.first { $0 is NSStepper } as? NSStepper)
        XCTAssertEqual(stepper.doubleValue, 260)
        XCTAssertEqual(stepper.maxValue, 4000)
        field.stringValue = "180"
        XCTAssertEqual(stepper.doubleValue, 180)
        stepper.doubleValue = 181
        stepper.sendAction(stepper.action, to: stepper.target)
        XCTAssertEqual(field.doubleValue, 181)
        field.isEnabled = false
        XCTAssertFalse(stepper.isEnabled)
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusFiniteValueTests: XCTestCase {
    func testStepperRejectsNonFiniteAndOverflowingInput() {
        for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -0.5] {
            XCTAssertNil(OnePlusStepperField.nativeValue(value, in: Int.min...Int.max))
        }
        XCTAssertEqual(OnePlusStepperField.nativeValue(0, in: 0...10), 0)
        XCTAssertEqual(OnePlusStepperField.nativeValue(10, in: 0...10), 10)
        XCTAssertNil(OnePlusStepperField.nativeValue(11, in: 0...10))
        XCTAssertNil(OnePlusStepperField.nextValue(Int.max, by: 1, in: Int.min...Int.max))
        XCTAssertNil(OnePlusStepperField.nextValue(Int.min, by: -1, in: Int.min...Int.max))
        XCTAssertEqual(OnePlusStepperField.nextValue(0, by: 1, in: 0...10), 1)
    }

    func testNativeNumberFieldKeepsFiniteValueAndLimits() throws {
        let field = OnePlusNativeStepperField(frame: CGRect(x: 0, y: 0, width: 100, height: 28))
        field.awakeFromNib()
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: Double.nan)
        formatter.maximum = NSNumber(value: Double.infinity)
        field.formatter = formatter
        let stepper = try XCTUnwrap(field.subviews.compactMap { $0 as? NSStepper }.first)
        for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, 0, 20] {
            field.doubleValue = value
            field.layout()
            XCTAssertTrue(field.doubleValue.isFinite)
            XCTAssertTrue(stepper.doubleValue.isFinite)
            XCTAssertTrue(stepper.minValue.isFinite)
            XCTAssertTrue(stepper.maxValue.isFinite)
            XCTAssertTrue((stepper.minValue...stepper.maxValue).contains(stepper.doubleValue))
        }
    }

    func testMetricLabelsDoNotBecomeGeometry() {
        for value in ["nan", "inf", "-inf", "0", ""] {
            let host = NSHostingView(rootView: OnePlusMetricTile("Metric", systemImage: "cpu", value: value)
                .frame(width: 240))
            XCTAssertTrue(host.fittingSize.width.isFinite)
            XCTAssertTrue(host.fittingSize.height.isFinite)
        }
    }
}

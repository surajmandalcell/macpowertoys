import AppKit
import XCTest
@testable import OnePlusUI

@MainActor final class OnePlusNativeFormTests: XCTestCase {
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

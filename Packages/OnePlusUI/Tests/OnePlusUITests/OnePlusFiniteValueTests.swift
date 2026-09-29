import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusFiniteValueTests: XCTestCase {
    func testChartRangesKeepEveryPathPointFinite() {
        let samples: [[Double]] = [[], [0, 0], [.nan, .infinity, -.infinity],
                                  [0, .nan, 50, .infinity, 100],
                                  [-Double.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude]]
        let ranges: [ClosedRange<Double>] = [0...100, 0...0, -.infinity ... .infinity,
                                            -Double.greatestFiniteMagnitude ... .greatestFiniteMagnitude]
        for values in samples {
            for range in ranges {
                let paths = OnePlusChartPaths.cached(values: values, range: range)
                for path in [paths.line, paths.area] {
                    path.forEach { element in
                        let points: [CGPoint]
                        switch element {
                        case .move(let point), .line(let point): points = [point]
                        case .quadCurve(let point, let control): points = [point, control]
                        case .curve(let point, let control1, let control2): points = [point, control1, control2]
                        case .closeSubpath: points = []
                        }
                        for point in points {
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(values), \(range): \(point)")
                            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
                        }
                    }
                }
            }
        }
    }

    func testMenuTileGeometryRejectsInvalidDimensions() {
        for width in [CGFloat.nan, .infinity, -.infinity, -1, 0, 338] {
            for span in [Int.min, 0, 1, 3, Int.max] {
                let width = OnePlusMenuMetrics.columnWidth(span: span, available: width)
                XCTAssertTrue(width.isFinite && width >= 0)
            }
        }
        for height in [CGFloat.nan, .infinity, -.infinity, -1, 0, 70] {
            let tile = OnePlusMenuTile(height: height) { Text("Metric") }
            XCTAssertTrue(tile.height.isFinite && tile.height >= 0)
        }
    }

    func testEmptyAndInvalidDataKeepFiniteViewSizes() {
        for values: [Double] in [[], [0, 0], [.nan, .infinity, -.infinity], [.greatestFiniteMagnitude, .greatestFiniteMagnitude]] {
            let host = NSHostingView(rootView: VStack {
                OnePlusUsageBar(value: values.first ?? 0)
                OnePlusSegmentBar(values: values, colors: [])
                OnePlusSparkline(values: values).frame(height: 40)
                OnePlusAreaChart(values: values).frame(height: 60)
            }.frame(width: 240))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(host.fittingSize.width.isFinite)
            XCTAssertTrue(host.fittingSize.height.isFinite)
        }
    }

    func testTablesAndPanelsRejectInvalidDimensions() {
        for dimension in [CGFloat.nan, .infinity, -.infinity, -1, 0, 120] {
            let column = OnePlusGridColumn("Value", width: dimension)
            XCTAssertTrue(column.width.isFinite && column.width >= 0)

            let table = NSHostingView(rootView: OnePlusGridTable(columns: [column], rows: [["Sample"]]))
            XCTAssertTrue(table.fittingSize.width.isFinite && table.fittingSize.height.isFinite)

            let panel = NSHostingView(rootView: OnePlusMenuPanel(maximumHeight: dimension) {
                EmptyView()
            } actions: {
                EmptyView()
            } content: {
                Text("Sample")
            })
            XCTAssertTrue(panel.fittingSize.width.isFinite && panel.fittingSize.height.isFinite)
        }
    }

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

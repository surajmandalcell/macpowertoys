import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

/// The Hold chart and the Hold field driven by real events in an offscreen window that never becomes key, so the
/// owner's front app keeps focus. Set FAN_SHOT_DIR to save the Fan page at 2x in Light and Dark.
@MainActor
final class FanHoldInteractionTests: XCTestCase {
    private let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 600, height: 240), styleMask: .borderless,
                                  backing: .buffered, defer: false)

    override func tearDown() async throws { window.close() }

    private func show<Content: View>(_ view: Content, size: CGSize, appearance: NSAppearance.Name = .aqua) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setContentSize(size)
        host.frame = CGRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        settle()
        return host
    }

    private func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func send(_ type: NSEvent.EventType, _ point: CGPoint) {
        let height = window.contentView?.bounds.height ?? 0
        let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: height - point.y), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        window.sendEvent(try! XCTUnwrap(event))
        settle(0.02)
    }

    /// 600 pt wide over 30-90 °C: 10 pt a degree, so 62 °C sits at x 320 and 48 °C at x 180.
    func testDraggingTheHoldChartSetsFortyEight() {
        var saved: [Double] = []
        _ = show(FanCurveEditor(curve: FanHold.displayCurve(target: 62), nowCelsius: nil, nowChip: nil, hold: 62,
                                setHold: { saved.append($0) }) { _ in },
                 size: CGSize(width: 600, height: FanCurveEditor.height))
        send(.leftMouseDown, CGPoint(x: 320, y: 120))
        for step in 1...14 { send(.leftMouseDragged, CGPoint(x: 320 - CGFloat(step) * 10, y: 120)) }
        send(.leftMouseUp, CGPoint(x: 180, y: 120))
        settle(0.2)
        XCTAssertEqual(saved, [48], "One save on release, at the degree under the pointer")

        send(.leftMouseDown, CGPoint(x: 20, y: 120))
        send(.leftMouseUp, CGPoint(x: 20, y: 120))
        settle(0.2)
        XCTAssertEqual(saved.last, FanHold.range.lowerBound, "A click past the range holds its floor, never nothing")
    }

    /// The page's Hold field: type 48, press Return, and the value lands; a refused value keeps the old one.
    func testTypingFortyEightAndReturnSetsHold() throws {
        var value = 62
        let binding = Binding(get: { value }, set: { value = $0 })
        let host = show(OnePlusStepperField("Hold at", value: binding, in: Int(FanHold.range.lowerBound)...Int(FanHold.range.upperBound),
                                            unit: "°C").fixedSize(),
                        size: CGSize(width: 200, height: 40))
        let field = try XCTUnwrap(Self.textField(in: host))
        for (typed, expected) in [("48", 48), ("12", 48)] {
            XCTAssertTrue(window.makeFirstResponder(field))
            settle()
            let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
            editor.selectAll(nil)
            editor.insertText(typed, replacementRange: editor.selectedRange())
            let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: window.windowNumber, context: nil, characters: "\r",
                                                       charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            window.sendEvent(enter)
            settle(0.2)
            XCTAssertEqual(value, expected, "Typed \(typed) then Return")
        }
    }

    func testRenderFanPageShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["FAN_SHOT_DIR"] else { throw XCTSkip("FAN_SHOT_DIR not set") }
        let size = CGSize(width: 760, height: 620)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (mode, hold) in [("cool", Optional(FanHold.coolTarget)), ("balanced", FanHold.balancedTarget), ("hold", 55)] {
                let view = VStack(spacing: 12) {
                    FanCurveEditor(curve: FanHold.displayCurve(target: hold ?? 62), nowCelsius: 51, nowChip: "CPU avg 51 °C · 2,840 RPM",
                                   hold: hold, setHold: { _ in }) { _ in }
                }
                .padding(20).background(OnePlusLinearColor.window)
                let host = show(view, size: size, appearance: appearance)
                settle(0.3)
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("chart-\(mode)-\(name).png"))
            }
        }
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap(textField(in:)).first
    }
}

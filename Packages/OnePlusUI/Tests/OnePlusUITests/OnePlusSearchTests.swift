import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusSearchTests: XCTestCase {
    func testSearchMouseDownReturnsWithoutReenteringContainer() throws {
        let view = CountingSearchView(frame: NSRect(x: 0, y: 0, width: 260, height: 32))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 260, height: 32),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.field.stringValue = "existing query"
        view.layoutSubtreeIfNeeded()

        // Native controls forward unhandled mouse events through nextResponder.
        // Bound reentry in this test so the original defect fails without hanging.
        for target in [view, view.field] {
            view.mouseDownCount = 0
            if target === view.field {
                view.field.isEditable = false
                view.field.isSelectable = false
            }
            let point = target === view ? NSPoint(x: 2, y: 2) : NSPoint(x: view.field.frame.midX, y: view.field.frame.midY)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
            target.mouseDown(with: event)
            XCTAssertEqual(view.mouseDownCount, 1, "A search click must not cycle through the container.")
        }
        view.field.isEditable = true
        view.field.isSelectable = true
        window.makeFirstResponder(nil)
        view.mouseDownCount = 0
        let point = view.convert(NSPoint(x: view.field.frame.midX, y: view.field.frame.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: point, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp,
            location: point, modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        NSApplication.shared.postEvent(up, atStart: true)
        view.field.mouseDown(with: down)
        XCTAssertLessThanOrEqual(view.mouseDownCount, 1, "Editable field clicks must return without a cycle.")
        _ = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
        XCTAssertFalse(window.isVisible)
    }

    func testExplicitFindSelectsTheCurrentQuery() throws {
        let root = { (trigger: Int) in OnePlusSidebarSearch(text: .constant("existing query"), focusTrigger: trigger) }
        let host = NSHostingView(rootView: root(0))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 260, height: 32),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.rootView = root(1)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 14))
        XCTAssertFalse(window.isVisible)
    }

    func testSearchBridgeKeepsCompositionUntilExternalValueCanApply() throws {
        let view = OnePlusSearchView(frame: CGRect(x: 0, y: 0, width: 260, height: 28))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.field.stringValue = "before"
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.makeFirstResponder(view.field))
        let editor = try XCTUnwrap(view.field.currentEditor() as? NSTextView)
        var published = "before"
        view.changed = { published = $0 }
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 6))
        view.updateText("external")
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "あ")
        editor.insertText("い", replacementRange: editor.markedRange())
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view.field))
        XCTAssertEqual(editor.string, "external")
        XCTAssertEqual(published, "external")
    }

    func testSearchTextAndEditorStayCentered() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for height in [CGFloat(28), 32] {
                for fontSize in [CGFloat(12), 10.5] {
                    let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 260, height: height),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    let view = OnePlusSearchView(frame: NSRect(x: 0, y: 0, width: 260, height: height))
                    window.contentView = view
                    window.appearance = NSAppearance(named: appearance)
                    view.field.font = .systemFont(ofSize: fontSize)
                    view.field.placeholderString = "Find a process"
                    view.hint.stringValue = "⌘K"
                    view.hint.isHidden = height == 28
                    view.layoutSubtreeIfNeeded()
                    let cell = try XCTUnwrap(view.field.cell as? NSSearchFieldCell)
                    let lineHeight = NSLayoutManager().defaultLineHeight(for: try XCTUnwrap(view.field.font))
                    for text in ["", "Find a process"] {
                        view.field.stringValue = text
                        for focused in [false, true] {
                            XCTAssertTrue(window.makeFirstResponder(focused ? view.field : nil))
                            let rect = cell.searchTextRect(forBounds: view.field.bounds)
                            XCTAssertEqual(rect.height, lineHeight, accuracy: 0.5)
                            XCTAssertEqual(view.field.convert(rect, to: view).midY, height / 2, accuracy: 0.5)
                            if focused {
                                let editor = try XCTUnwrap(view.field.currentEditor() as? NSTextView)
                                XCTAssertEqual(editor.convert(editor.bounds, to: view).midY, height / 2, accuracy: 0.5)
                                if !text.isEmpty, let layout = editor.layoutManager, let container = editor.textContainer {
                                    layout.ensureLayout(for: container)
                                    let line = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                                        .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                                    XCTAssertEqual(editor.convert(line, to: view).midY, height / 2, accuracy: 0.5)
                                    XCTAssertEqual(editor.convert(line, to: view).minX, view.field.convert(rect, to: view).minX, accuracy: 0.5)
                                }
                            }
                            if let directory = ProcessInfo.processInfo.environment["ONEPLUS_SEARCH_CAPTURE_DIR"],
                               let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 520, pixelsHigh: Int(height * 2),
                                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                                bitmap.size = view.bounds.size
                                view.cacheDisplay(in: view.bounds, to: bitmap)
                                let name = "\(appearance.rawValue)-\(Int(height))-\(fontSize)-\(text.isEmpty ? "placeholder" : "text")-\(focused).png"
                                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
                            }
                        }
                    }
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
}

@MainActor
private final class CountingSearchView: OnePlusSearchView {
    var mouseDownCount = 0
    override func mouseDown(with event: NSEvent) {
        mouseDownCount += 1
        if mouseDownCount == 1 { super.mouseDown(with: event) }
    }
}

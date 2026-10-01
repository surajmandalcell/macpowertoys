import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusSettingRowTests: XCTestCase {
    func testMultilineErrorKeepsFieldCenteredInItsFixedRow() throws {
        for caption in [String?.none, "Units"] {
            let pitch: CGFloat = caption == nil ? 44 : 56
            let host = NSHostingView(rootView: OnePlusCard {
                OnePlusSettingRow("Limit", caption: caption) {
                    OnePlusTextField("Limit", text: .constant("invalid draft"),
                                     error: String(repeating: "Enter a valid limit. ", count: 8))
                }
                OnePlusSettingRow("Next", separator: false) { SettingControlProbe().frame(height: 28) }
            }.frame(maxHeight: .infinity, alignment: .top))
            host.frame = CGRect(x: 0, y: 0, width: 420, height: 240)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
            let field = try XCTUnwrap(descendants(host).compactMap { $0 as? OnePlusTextInputView }.first)
            let frame = field.convert(field.bounds, to: host)
            XCTAssertEqual(frame.height, field.intrinsicContentSize.height, accuracy: 0.5)
            XCTAssertEqual(frame.midY, pitch / 2, accuracy: 0.5)
            XCTAssertEqual(field.stringValue, "invalid draft")
            XCTAssertGreaterThan(host.fittingSize.height, pitch + 44, "The full recovery message must remain below the fixed rows")
        }
    }

    func testHorizontalPathRowKeepsIntrinsicActionAndFixedPitch() throws {
        for width in [CGFloat(338), 976] {
            let host = NSHostingView(rootView: OnePlusPathSettingRow("Backup", path: String(repeating: "/long/path", count: 50),
                layout: .horizontal, help: "Backup location") {
                    SettingControlProbe().frame(width: 48, height: 28)
                })
            host.frame = CGRect(x: 0, y: 0, width: width, height: 44)
            host.layoutSubtreeIfNeeded()
            let control = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "control" })
            let frame = control.convert(control.bounds, to: host)
            XCTAssertEqual(host.fittingSize.height, 44)
            XCTAssertEqual(frame.width, 48)
            XCTAssertEqual(frame.maxX, width - 16, accuracy: 0.5)
            XCTAssertEqual(frame.midY, 22, accuracy: 0.5)
        }
    }

    func testCompactHeaderAndSettingControlShareTheTwelvePointInset() throws {
        let host = NSHostingView(rootView: OnePlusCard {
            OnePlusCardHeader("Fan", systemImage: "fan") { SettingControlProbe().frame(width: 40) }
            OnePlusSettingRow("Preset") { SettingControlProbe().frame(maxWidth: .infinity) }
        }.onePlusDensity(.compact))
        host.frame = CGRect(x: 0, y: 0, width: 420, height: 84)
        host.layoutSubtreeIfNeeded()
        let controls = descendants(host).filter { $0.identifier?.rawValue == "control" }
        XCTAssertEqual(controls.count, 2)
        for control in controls {
            XCTAssertEqual(control.convert(control.bounds, to: host).maxX, 420 - 12, accuracy: 0.5)
        }
    }
    func testCaptionUsesRemainingWidthAndControlColumnStaysFixed() throws {
        let caption = "Default: " + String(repeating: "W", count: 200)
        for width in [CGFloat(480), 976] {
            for column in [CGFloat(160), 180] {
                for hasReset in [false, true] {
                    let host = NSHostingView(rootView: OnePlusSettingRow("Preference", caption: caption,
                        help: "Preference help", reset: hasReset ? {} : nil, controlWidth: column) {
                            SettingControlProbe().frame(maxWidth: .infinity).frame(height: 28)
                        }.frame(width: width).background(OnePlusColor.panel))
                    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: 56),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    defer { window.close() }
                    host.appearance = NSAppearance(named: .darkAqua)
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    let control = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "control" })
                    let controlRect = control.convert(control.bounds, to: host)
                    XCTAssertEqual(controlRect.width, column, accuracy: 0.5)
                    XCTAssertEqual(controlRect.maxX, width - 16, accuracy: 0.5)
                    let captionWidth = width - 32 - column - 16
                    let reference = NSHostingView(rootView: Text(caption).onePlusText(.caption).lineLimit(1)
                        .frame(width: captionWidth, height: 56, alignment: .leading).background(OnePlusColor.panel))
                    reference.appearance = host.appearance
                    reference.frame = CGRect(x: 0, y: 0, width: captionWidth, height: 56)
                    reference.layoutSubtreeIfNeeded()
                    let expected = try captionRightEdge(reference, in: reference.bounds) + 16
                    let actual = try captionRightEdge(host, in: CGRect(x: 16, y: 33, width: captionWidth, height: 20))
                    XCTAssertEqual(actual, expected, accuracy: 1)
                    XCTAssertEqual(host.fittingSize.height, 56)
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func captionRightEdge(_ host: NSView, in rect: CGRect) throws -> CGFloat {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        var ink = NSColor.clear, panel = NSColor.clear
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            ink = NSColor(OnePlusColor.muted).usingColorSpace(.deviceRGB)!
            panel = NSColor(OnePlusColor.panel).usingColorSpace(.deviceRGB)!
        }
        var lastPixel: Int?
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent > panel.redComponent + 0.05,
                   color.redComponent < ink.redComponent + 0.02 {
                    lastPixel = max(lastPixel ?? x, x)
                }
            }
        }
        return CGFloat(try XCTUnwrap(lastPixel)) / scale
    }
}

private struct SettingControlProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("control")
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

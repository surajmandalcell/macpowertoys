import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusHeaderRowTests: XCTestCase {
    func testHeaderRecipesCenterStatusSwitchesAndSmallerButtons() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for density in OnePlusDensity.allCases {
                for scale in [CGFloat(1), 2] {
                    let actions = OnePlusHeaderActions {
                        OnePlusStatus("HILT", state: .success).overlay { HeaderRowProbe("status") }
                        Toggle("HILT", isOn: .constant(true)).toggleStyle(OnePlusSwitchStyle())
                            .overlay { HeaderRowProbe("switch") }
                        Button("Small") {}.buttonStyle(OnePlusButtonStyle(size: .small))
                            .overlay { HeaderRowProbe("small") }
                        Button("Refresh") {}.buttonStyle(OnePlusButtonStyle(height: 28))
                            .overlay { HeaderRowProbe("button") }
                        OnePlusSelect(choices: [("one", "One")], selection: .constant("one"),
                                      width: 70, accessibilityLabel: "Select")
                            .overlay { HeaderRowProbe("select") }
                        OnePlusSearchField(prompt: "Search", text: .constant(""), width: 90)
                            .overlay { HeaderRowProbe("search") }
                        OnePlusTextField("Value", text: .constant("")).frame(width: 70)
                            .overlay { HeaderRowProbe("field") }
                        ProgressView().controlSize(.small).overlay { HeaderRowProbe("progress") }
                    }
                    let recipes = [
                        AnyView(OnePlusPageHeader(title: "Devices") { actions }),
                        AnyView(OnePlusToolPageHeader(title: "Devices", subtitle: "Description") {
                            Color.clear
                        } actions: { actions }),
                        AnyView(OnePlusAppletTitlebar(title: "Awake") { actions })
                    ]
                    for recipe in recipes {
                        let host = NSHostingView(rootView: recipe.onePlusDensity(density)
                            .environment(\.displayScale, scale)
                            .frame(width: 900, height: 100, alignment: .topLeading)
                            .background(OnePlusColor.window))
                        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 900, height: 100),
                                              styleMask: .borderless, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.appearance = NSAppearance(named: appearance)
                        window.contentView = host
                        defer { window.close() }
                        host.layoutSubtreeIfNeeded()
                        func frame(_ name: String) throws -> CGRect {
                            let node = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == name })
                            return node.convert(node.bounds, to: host)
                        }
                        let button = try frame("button")
                        XCTAssertEqual(button.minY, 20, accuracy: 0.01)
                        for name in ["status", "switch", "small", "select", "search", "field", "progress"] {
                            XCTAssertEqual(try frame(name).midY, button.midY, accuracy: 0.5,
                                           "\(name) \(density) \(appearance) \(scale)x")
                        }
                        XCTAssertEqual(try frame("button").minX - frame("small").maxX, 12, accuracy: 0.01)
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                            pixelsWide: Int(900 * scale), pixelsHigh: Int(100 * scale), bitsPerSample: 8,
                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                            bytesPerRow: 0, bitsPerPixel: 0))
                        bitmap.size = host.bounds.size
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let status = try frame("status")
                        func center(in xRange: Range<CGFloat>) throws -> CGFloat {
                            var rows: [Int] = []
                            for y in 0..<bitmap.pixelsHigh {
                                for x in Int(xRange.lowerBound * scale)..<Int(xRange.upperBound * scale) {
                                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                                    if color.greenComponent - max(color.redComponent, color.blueComponent) > 0.06 {
                                        rows.append(y)
                                    }
                                }
                            }
                            return CGFloat(try XCTUnwrap(rows.min()) + XCTUnwrap(rows.max()) + 1) / (2 * scale)
                        }
                        let dot = try center(in: status.minX..<(status.minX + 4))
                        let caption = try center(in: (status.minX + 10)..<status.maxX)
                        XCTAssertEqual(dot, caption, accuracy: 0.5)
                        XCTAssertEqual(caption, button.midY, accuracy: 0.5)
                    }
                }
            }
        }
    }

    func testCaptionAndTwentyEightPointButtonShareThePaintedCenter() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for scale in [CGFloat(1), 2] {
                let host = NSHostingView(rootView: OnePlusPageHeader(title: "Devices") {
                    Text("HILT").onePlusText(.caption, color: .green)
                    Button("Refresh") {}.buttonStyle(OnePlusButtonStyle(height: 28))
                        .overlay { HeaderRowProbe("button") }
                }.environment(\.displayScale, scale)
                    .frame(width: 600, height: 100, alignment: .topLeading)
                    .background(OnePlusColor.window))
                let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 600, height: 100),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                defer { window.close() }
                host.layoutSubtreeIfNeeded()
                let button = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "button" })
                let frame = button.convert(button.bounds, to: host)
                XCTAssertEqual(frame.minY, 20, accuracy: 0.01)
                XCTAssertEqual(frame.height, 28, accuracy: 0.01)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(600 * scale), pixelsHigh: Int(100 * scale), bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = host.bounds.size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                var rows: [Int] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        if color.greenComponent - max(color.redComponent, color.blueComponent) > 0.3 {
                            rows.append(y)
                        }
                    }
                }
                let center = CGFloat(try XCTUnwrap(rows.min()) + XCTUnwrap(rows.max()) + 1) / (2 * scale)
                XCTAssertEqual(center, frame.midY, accuracy: 0.5, "\(appearance) \(scale)x")
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct HeaderRowProbe: NSViewRepresentable {
    let name: String
    init(_ name: String) { self.name = name }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

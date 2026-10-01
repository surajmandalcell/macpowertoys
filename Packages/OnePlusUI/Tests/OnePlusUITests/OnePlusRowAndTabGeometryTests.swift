import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusRowAndTabGeometryTests: XCTestCase {
    func testTabHoverExpandsOnlyPaintAndKeepsLabelsAndUnderlineFixed() throws {
        for density in OnePlusDensity.allCases {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                var frames: [[CGRect]] = []
                var renders: [NSBitmapImageRep] = []
                for state in [OnePlusControlState.rest, .hover] {
                    let markers = [NSView(), NSView()]
                    let host = NSHostingView(rootView: HStack(spacing: 22) {
                        ForEach(markers.indices, id: \.self) { index in
                            Button {} label: {
                                GeometryProbe(view: markers[index]).frame(width: 80, height: 16)
                            }.buttonStyle(OnePlusTabButtonStyle(selected: index == 0))
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 24).environment(\.onePlusControlState, state)
                        .onePlusDensity(density)
                        .background(OnePlusColor.window))
                    let window = attach(host, width: 400, height: 36, appearance: appearance)
                    defer { window.close() }
                    frames.append(markers.map { $0.convert($0.bounds, to: host) })
                    renders.append(try bitmap(host))
                }
                XCTAssertEqual(frames[0], frames[1])
                let label = frames[0][0]
                let scale = CGFloat(renders[0].pixelsWide) / 400
                func difference(_ x: CGFloat, _ y: CGFloat) throws -> CGFloat {
                    let rest = try XCTUnwrap(renders[0].colorAt(x: Int(x * scale), y: Int(y * scale)))
                    let hover = try XCTUnwrap(renders[1].colorAt(x: Int(x * scale), y: Int(y * scale)))
                    return abs(rest.redComponent - hover.redComponent)
                }
                XCTAssertGreaterThan(try difference(label.minX - 7, label.midY), 0.01)
                XCTAssertGreaterThan(try difference(label.maxX + 7, label.midY), 0.01)
                XCTAssertGreaterThan(try difference(label.midX, label.minY - 3), 0.01)
                XCTAssertGreaterThan(try difference(label.midX, label.maxY + 3), 0.01)
                XCTAssertEqual(try difference(label.minX - 9, label.midY), 0, accuracy: 0.001)
                XCTAssertEqual(try difference(label.midX, label.minY - 5), 0, accuracy: 0.001)
                for x in stride(from: label.minX, to: label.maxX, by: 1) {
                    XCTAssertEqual(try difference(x, 35), 0, accuracy: 0.001)
                }
            }
        }
    }

    func testRowHoverCoversTrailingActionsAndKeepsGeometryFixed() throws {
        for density in OnePlusDensity.allCases {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                var frames: [CGRect] = []
                var renders: [NSBitmapImageRep] = []
                for state in [OnePlusControlState.rest, .hover] {
                    let marker = NSView()
                    let host = NSHostingView(rootView: OnePlusDeviceNavRow(
                        "External disk", subtitle: "/Volumes/Work", systemImage: "externaldrive",
                        selected: false, locked: true, action: {}
                    ) {
                        GeometryProbe(view: marker).frame(width: 24, height: 24)
                    }.environment(\.onePlusControlState, state).onePlusDensity(density)
                        .background(OnePlusColor.panel))
                    let window = attach(host, width: 300, height: 56, appearance: appearance)
                    defer { window.close() }
                    frames.append(marker.convert(marker.bounds, to: host))
                    renders.append(try bitmap(host))
                }
                XCTAssertEqual(frames[0], frames[1])
                let scale = CGFloat(renders[0].pixelsWide) / 300
                for x: CGFloat in [1, 150, 275, 298] {
                    let before = try XCTUnwrap(renders[0].colorAt(x: Int(x * scale), y: Int(28 * scale)))
                    let after = try XCTUnwrap(renders[1].colorAt(x: Int(x * scale), y: Int(28 * scale)))
                    XCTAssertGreaterThan(abs(after.redComponent - before.redComponent), 0.01)
                }
            }
        }
    }

    func testSingleMenuTileRowCentersInEveryDeclaredHeight() {
        for height: CGFloat in [34, 51, 70] {
            let marker = NSView()
            let host = NSHostingView(rootView: OnePlusMenuTile(span: 2, height: height, textured: false) {
                GeometryProbe(view: marker).frame(width: 40, height: 16)
            })
            let window = attach(host, width: OnePlusMenuMetrics.columnWidth(span: 2), height: height)
            defer { window.close() }
            let rect = marker.convert(marker.bounds, to: host)
            XCTAssertEqual(rect.midY, height / 2, accuracy: 0.5)
            XCTAssertEqual(rect.minX, 8, accuracy: 0.01)
        }
    }

    func testRelatedMenuItemActionsShareOneRow() {
        let markers = [NSView(), NSView()]
        let host = NSHostingView(rootView: OnePlusMenuItemCard("Host", status: "Connected", metrics: []) {
            EmptyView()
        } actions: {
            GeometryProbe(view: markers[0]).frame(width: 48, height: 24)
            GeometryProbe(view: markers[1]).frame(width: 48, height: 24)
        })
        let window = attach(host, width: 300, height: 110)
        defer { window.close() }
        let frames = markers.map { $0.convert($0.bounds, to: host) }
        XCTAssertEqual(frames[0].midY, frames[1].midY, accuracy: 0.01)
        XCTAssertLessThan(frames[0].maxX, frames[1].minX)
    }

    func testStatMetadataUsesOneLineAndDensityPadding() {
        for density in OnePlusDensity.allCases {
            let host = NSHostingView(rootView: OnePlusStatCell("Used", value: "12 GB").onePlusDensity(density))
            let window = attach(host, width: 300, height: 70)
            defer { window.close() }
            XCTAssertLessThanOrEqual(host.fittingSize.height, density == .compact ? 44 : 52)
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testHistoryBackgroundCoversTileOutsideContentPaddingInBothAppearances() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            var renders: [NSBitmapImageRep] = []
            for values in [[], [50.0, 50.0]] {
                let host = NSHostingView(rootView: OnePlusMenuTile(height: 70, textured: false) {
                    Color.clear.frame(width: 1, height: 1)
                }.historyBackground(values: values))
                let window = attach(host, width: OnePlusMenuMetrics.columnWidth(span: 1), height: 70, appearance: appearance)
                defer { window.close() }
                renders.append(try bitmap(host))
            }
            let scale = CGFloat(renders[0].pixelsHigh) / 70
            for x in [2, renders[0].pixelsWide - 3] {
                let differences = try (30...38).map { y in
                    let rest = try XCTUnwrap(renders[0].colorAt(x: x, y: Int(CGFloat(y) * scale)))
                    let history = try XCTUnwrap(renders[1].colorAt(x: x, y: Int(CGFloat(y) * scale)))
                    return abs(rest.redComponent - history.redComponent) + abs(rest.blueComponent - history.blueComponent)
                }
                XCTAssertGreaterThan(differences.max() ?? 0, 0.01)
                XCTAssertLessThan(differences.max() ?? 0, 0.4)
            }
        }
    }

    func testMenuAndTableRowsHoverAcrossValuesAndControlsButNotWhenDisabled() throws {
        let rows: [(AnyView, CGFloat, CGFloat)] = [
            (AnyView(HStack { Text("CPU"); Spacer(); Text("24%"); Button("Open") {} }.onePlusTableRow()), 34, 16),
            (AnyView(OnePlusMenuControlRow("Awake", systemImage: "moon", caption: "Keep this Mac awake") {
                Button("Change") {}.buttonStyle(.plain)
            }), 44, 40),
            (AnyView(OnePlusMenuItemCard("Host", status: "Connected", metrics: [.init("CPU", value: "24", unit: "%")]) {
                OnePlusSparkline(values: [1, 3, 2]).frame(height: 24)
            } actions: { Button("Open") {} }), 110, 80)
        ]
        for (content, height, sampleY) in rows {
            var renders: [NSBitmapImageRep] = []
            for (state, disabled) in [(OnePlusControlState.rest, false), (.hover, false), (.rest, true), (.hover, true)] {
                let host = NSHostingView(rootView: content.disabled(disabled)
                    .environment(\.onePlusControlState, state).background(OnePlusColor.panel))
                let window = attach(host, width: 300, height: height)
                defer { window.close() }
                renders.append(try bitmap(host))
            }
            let scale = CGFloat(renders[0].pixelsWide) / 300
            for x: CGFloat in [2, 297] {
                let y = Int(sampleY * scale)
                let rest = try XCTUnwrap(renders[0].colorAt(x: Int(x * scale), y: y))
                let hover = try XCTUnwrap(renders[1].colorAt(x: Int(x * scale), y: y))
                let disabledRest = try XCTUnwrap(renders[2].colorAt(x: Int(x * scale), y: y))
                let disabledHover = try XCTUnwrap(renders[3].colorAt(x: Int(x * scale), y: y))
                XCTAssertGreaterThan(abs(rest.redComponent - hover.redComponent), 0.01, "Row height \(height), x \(x)")
                XCTAssertEqual(disabledRest.redComponent, disabledHover.redComponent, accuracy: 0.001)
            }
        }
    }

    func testSwiftUITableHoverUsesCompleteNativeRowAndRestoresItsBackground() throws {
        let host = NSHostingView(rootView: Table([OnePlusTableItem(id: "1", cells: [], symbol: "doc")]) {
            TableColumn("Name", value: \.id).width(120)
            TableColumn("Value") { _ in Text("42 MB") }.width(120)
        }.onePlusNativeTable())
        let window = attach(host, width: 300, height: 100)
        defer { window.close() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
        let row = try XCTUnwrap(table.rowView(atRow: 0, makeIfNecessary: true))
        let lines = try XCTUnwrap(table.subviews.compactMap { $0 as? OnePlusTableLines }.first)
        let background = row.backgroundColor
        let frame = row.frame
        let restingRender = try bitmap(row)
        lines.setHoveredRow(0)
        XCTAssertEqual(row.backgroundColor, NSColor(OnePlusColor.raised))
        XCTAssertEqual(row.frame, frame)
        let render = try bitmap(row)
        let scale = CGFloat(render.pixelsWide) / row.bounds.width
        let leading = try XCTUnwrap(render.colorAt(x: Int(2 * scale), y: Int(5 * scale)))
        let trailing = try XCTUnwrap(render.colorAt(x: render.pixelsWide - Int(2 * scale), y: Int(5 * scale)))
        let before = try XCTUnwrap(restingRender.colorAt(x: Int(2 * scale), y: Int(5 * scale)))
        XCTAssertGreaterThan(abs(leading.redComponent - before.redComponent), 0.01)
        XCTAssertEqual(leading.redComponent, trailing.redComponent, accuracy: 0.001)
        lines.setHoveredRow(-1)
        XCTAssertEqual(row.backgroundColor, background)
    }

    private func attach<V: View>(_ host: NSHostingView<V>, width: CGFloat, height: CGFloat,
                                 appearance: NSAppearance.Name = .darkAqua) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return window
    }

    private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

private struct GeometryProbe: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

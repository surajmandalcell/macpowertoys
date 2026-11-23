//
//  DemoRuler.swift
//  powertoys
//

#if MPT_DEMO
import AppKit
import OnePlusUI
import SwiftUI

/// The ruler measures a real demo window: Mac Tweaks opens, the ruler's zero corner snaps to its top left,
/// and the ruler grows to the window's size while the mouse ticks follow the growing corner and read out width
/// and height. The demo draws the ticks itself: the app never becomes active, and the owner's pointer is never read.
@MainActor
enum DemoRuler {
    private static let start = NSSize(width: 280, height: 200)
    private static let growSteps = 24
    private static let growDuration = 1.6
    private static let arrangeDelay = 0.25
    private static var measured = NSRect.zero

    static func seed() {}

    private static var controller: RulerController? { AppDelegate.current?.rulerManager.activeController }

    /// The ruler runs a little past the measured edge, like a real ruler laid against a box.
    private static let overhang = 24.0

    /// `size` is the measured span. The ticks sit one pixel past its last pixel (pixels count from 0), so the
    /// readouts show the full width and height.
    private static func resize(to size: NSSize) {
        controller?.updateDimensions(horizontalLength: size.width + overhang, verticalLength: size.height + overhang)
        controller?.drawMouseTick(at: NSPoint(x: measured.minX + size.width + 1, y: measured.maxY - size.height - 1))
    }

    /// Puts Mac Tweaks near the top right of the main screen and the ruler's zero corner on its top left.
    private static func arrange() {
        guard let target = NSApp.windows.filter({ $0.isVisible && !($0 is RulerWindow) })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let margin = 120.0
        target.setFrameOrigin(NSPoint(x: visible.maxX - target.frame.width - margin,
                                      y: visible.maxY - target.frame.height - margin))
        measured = target.frame
        controller?.align(at: NSPoint(x: measured.minX, y: measured.maxY))
        resize(to: start)
    }

    static var scene: DemoScene {
        let grow = (1...growSteps).map { index in
            let progress = Double(index) / Double(growSteps)
            let eased = 1 - pow(1 - progress, 3)
            return DemoStep(at: 1.0 + growDuration * progress) {
                resize(to: NSSize(width: start.width + (measured.width - start.width) * eased,
                                  height: start.height + (measured.height - start.height) * eased))
            }
        }
        return DemoScene(
            open: {
                ToolActionRouter.shared.open(toolID: "mac-tweaks", activateApp: false)
                ToolActionRouter.shared.open(toolID: "ruler", activateApp: false)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(arrangeDelay))
                    arrange()
                }
            },
            steps: grow,
            tail: 2.5
        )
    }

    private static var wireframe: NSWindow?

    /// A designer checking a wireframe: the ruler at its real default length, zero on the card's top left,
    /// and the tick on the card's bottom right corner, so it reads the card's true 320 x 240 pt.
    static var designScene: DemoScene {
        DemoScene(
            open: {
                ToolActionRouter.shared.open(toolID: "ruler", activateApp: false)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(arrangeDelay))
                    let lengths = RulerLayoutState.defaultLengths()
                    // The window lies under the whole ruler, so the full-length ruler never hangs over empty space.
                    let size = NSSize(width: DemoWireframe.card.minX + lengths.horizontal + 48,
                                      height: DemoWireframe.card.minY + lengths.vertical + 48)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                          backing: .buffered, defer: false)
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.contentView = NSHostingView(rootView: DemoWireframe(size: size))
                    let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
                    window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 40, y: visible.maxY - 40))
                    window.orderFront(nil)
                    wireframe = window
                    let zero = NSPoint(x: window.frame.minX + DemoWireframe.card.minX,
                                       y: window.frame.maxY - DemoWireframe.card.minY)
                    controller?.align(at: zero)
                    controller?.updateDimensions(horizontalLength: lengths.horizontal, verticalLength: lengths.vertical)
                    controller?.drawMouseTick(at: NSPoint(x: zero.x + DemoWireframe.card.width + 1,
                                                          y: zero.y - DemoWireframe.card.height - 1))
                }
            },
            steps: [],
            tail: 2.5
        )
    }
}

/// A gray-box app wireframe with known sizes: 320 x 240 pt cards with 16 pt padding and a 44 pt button.
private struct DemoWireframe: View {
    static let card = CGRect(x: 72, y: 104, width: 320, height: 240)
    private static let padding = 16.0
    private static let button = 44.0
    private static let gap = 24.0
    private static let rowPitch = 52.0
    let size: NSSize

    private var cards: Int { Int((size.width - Self.card.minX) / (Self.card.width + Self.gap)) }
    private var rows: Int { Int((size.height - Self.card.maxY - 32) / Self.rowPitch) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnePlusLinearColor.window
            box(CGRect(x: 96, y: 20, width: 160, height: 12), fill: OnePlusLinearColor.fillTrack)
            box(CGRect(x: Self.card.minX, y: 64, width: 220, height: 16), fill: OnePlusLinearColor.fillTrack)
            ForEach(0..<cards, id: \.self) { index in
                cardBoxes(at: Self.card.offsetBy(dx: Double(index) * (Self.card.width + Self.gap), dy: 0))
            }
            ForEach(0..<rows, id: \.self) { row in
                let top = Self.card.maxY + 32 + Double(row) * Self.rowPitch
                box(CGRect(x: Self.card.minX, y: top, width: Double(cards) * (Self.card.width + Self.gap) - Self.gap, height: 40),
                    fill: OnePlusLinearColor.fillGroup)
                box(CGRect(x: Self.card.minX + Self.padding, y: top + 14, width: 180 - Double(row % 4) * 24, height: 12),
                    fill: OnePlusLinearColor.fillTrack)
            }
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
    }

    @ViewBuilder private func cardBoxes(at card: CGRect) -> some View {
        let inner = card.width - 2 * Self.padding
        box(card, fill: OnePlusLinearColor.fillGroup)
        box(CGRect(x: card.minX + Self.padding, y: card.minY + Self.padding, width: inner, height: 112),
            fill: OnePlusLinearColor.fillTrack)
        box(CGRect(x: card.minX + Self.padding, y: card.minY + 140, width: 200, height: 10), fill: OnePlusLinearColor.fillTrack)
        box(CGRect(x: card.minX + Self.padding, y: card.minY + 158, width: 136, height: 10), fill: OnePlusLinearColor.fillTrack)
        box(CGRect(x: card.minX + Self.padding, y: card.maxY - Self.padding - Self.button, width: inner, height: Self.button),
            fill: OnePlusLinearColor.fillThumb)
    }

    private func box(_ rect: CGRect, fill: Color) -> some View {
        fill.frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}
#endif

//
//  DemoRuler.swift
//  powertoys
//

#if MPT_DEMO
import AppKit
import OnePlusUI

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

    /// Top of the first Color Picker history row, from the window top: titlebar, tab strip, search, and gaps.
    private static let firstRowTop = 130.0
    /// Row inset: the 16 pt card inset plus the 12 pt row padding, where the swatch starts.
    private static let swatchInset = 28.0

    /// A designer checking spacing, laid out tall: the vertical rule runs down beside the Color Picker history,
    /// zero on the first row's top, and the tick reads the 36 pt row height and the 28 pt swatch inset.
    static var designScene: DemoScene {
        DemoScene(
            open: {
                DemoColorPicker.addLatest()
                ToolActionRouter.shared.open(toolID: "color-picker", activateApp: false)
                ToolActionRouter.shared.open(toolID: "ruler", activateApp: false)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(arrangeDelay))
                    arrange()
                    let row = NSPoint(x: measured.minX, y: measured.maxY - firstRowTop)
                    controller?.align(at: row)
                    controller?.updateDimensions(horizontalLength: 200, verticalLength: 520)
                    controller?.drawMouseTick(at: NSPoint(x: row.x + swatchInset + 1,
                                                          y: row.y - OnePlusLinearMetrics.appletRow - 1))
                }
            },
            steps: [],
            tail: 2.5
        )
    }
}
#endif

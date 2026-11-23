import AppKit
import Foundation
import OnePlusUI
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case none
    case combined
    case separate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .combined: "Combined"
        case .separate: "Separate"
        }
    }
}

enum IndividualMenuBarActivation: Equatable {
    case openTool(String)
    case execute(ToolActionID)
}

struct IndividualMenuBarRefreshPlan: Equatable {
    let insertions: [IndividualMenuBarTool]
    let removals: [IndividualMenuBarTool]

    init(current: Set<IndividualMenuBarTool>, desired: [IndividualMenuBarTool]) {
        let desiredSet = Set(desired)
        insertions = desired.filter { !current.contains($0) }
        removals = IndividualMenuBarTool.allCases.filter {
            current.contains($0) && !desiredSet.contains($0)
        }
    }
}

enum IndividualMenuBarTool: String, CaseIterable, Identifiable {
    case cloudSync = "rclone"
    case awake
    case colorPicker = "color-picker"
    case textExtractor = "text-extractor"
    case inputDevices = "input-devices"

    var id: String { rawValue }
    var preferenceKey: String { "tool.\(rawValue).menuBarDisplayMode" }
    var legacyPreferenceKey: String { "tool.\(rawValue).showMenuBarIcon" }
    var autosaveName: String { "MacPowerToys.\(rawValue)" }

    func displayMode(in defaults: UserDefaults = .standard) -> MenuBarDisplayMode {
        if let rawValue = defaults.string(forKey: preferenceKey),
           let mode = MenuBarDisplayMode(rawValue: rawValue) {
            return mode
        }
        if defaults.bool(forKey: legacyPreferenceKey) {
            return .separate
        }
        return self == .cloudSync || self == .awake ? .combined : .none
    }

    func usesMenuBarMode(
        _ mode: MenuBarDisplayMode,
        enabled: Bool,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        enabled && displayMode(in: defaults) == mode
    }

    var title: String {
        switch self {
        case .cloudSync: "RSync UI"
        case .awake: "Awake"
        case .colorPicker: "Color Picker"
        case .textExtractor: "Text Extractor"
        case .inputDevices: "Input Devices"
        }
    }

    var symbol: String {
        switch self {
        case .cloudSync: ToolGlyph.cloudSync.symbol
        case .awake: ToolGlyph.awake.symbol
        case .colorPicker: ToolGlyph.colorPicker.symbol
        case .textExtractor: ToolGlyph.textExtractor.symbol
        case .inputDevices: ToolGlyph.inputDevices.symbol
        }
    }

    /// Traced `MenuBarGlyph*` asset; Awake swaps between its open and closed eye.
    var menuBarGlyph: String {
        switch self {
        case .cloudSync: "MenuBarGlyphCloud"
        case .awake: "MenuBarGlyphAwakeOpen"
        case .colorPicker: "MenuBarGlyphColorPicker"
        case .textExtractor: "MenuBarGlyphTextExtractor"
        case .inputDevices: "MenuBarGlyphInputDevices"
        }
    }

    /// The tool's own "Animate menu bar icon" switch; only tools with a motion have one.
    var animationPreferenceKey: String? {
        switch self {
        case .awake: "tool.awake.animatedMenuBarIcon"
        case .cloudSync: "tool.rclone.animatedMenuBarIcon"
        default: nil
        }
    }

    /// On/off tools run their action on left click and open the panel on right click (DESIGN.md "Status icon").
    var quickAction: ToolActionID? {
        switch self {
        case .awake: .awakeToggle
        case .colorPicker: .colorPickerPick
        case .textExtractor: .textExtractorCapture
        default: nil
        }
    }

    var actionTitle: String? {
        switch self {
        case .colorPicker: "Pick Color"
        case .textExtractor: "Extract Text"
        default: nil
        }
    }

    var activation: IndividualMenuBarActivation {
        quickAction.map(IndividualMenuBarActivation.execute) ?? .openTool(id)
    }
}

/// Awake's menu bar symbol, chosen on the Awake page. The accent pulses while Awake is on.
enum AwakeMenuBarStyle: String, CaseIterable {
    case eye
    case cup

    static let key = "tool.awake.menuBarStyle"

    var title: String { self == .eye ? "Eye" : "Cup" }
    var on: String { self == .eye ? "MenuBarGlyphAwakeOpen" : "MenuBarGlyphAwakeCup" }
    var accent: String { self == .eye ? "MenuBarGlyphAwakeRays" : "MenuBarGlyphAwakeSteam" }
    var off: String { self == .eye ? "MenuBarGlyphAwakeClosed" : "MenuBarGlyphAwakeCup" }
}

@MainActor
final class IndividualMenuBarController: NSObject {
    static let shared = IndividualMenuBarController()
    static weak var current: IndividualMenuBarController?

    private let defaults = UserDefaults.standard
    private var statusItems: [IndividualMenuBarTool: NSStatusItem] = [:]
    private var popovers: [IndividualMenuBarTool: OnePlusMenuPresenter] = [:]
    private var observers: [NSObjectProtocol] = []
    private var pulseRays: NSImageView?
    private var pulseStyle: AwakeMenuBarStyle?
    private var cloudBudget = MenuBarAttentionBudget()
    private var cloudDraw: NSImageView?
    private var cloudTimer: Timer?
    private var screensAsleep = false
    static let animatedIconsKey = "menuBar.animatedIcons"

    var statusItemOwnerCount: Int { statusItems.count }
    var observerOwnerCount: Int { observers.count }

    private override init() {
        super.init()
        Self.current = self
    }

    func start() {
        guard observers.isEmpty else {
            refresh()
            return
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(
                forName: .toolEnablementChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, (note.object as? NSWindow) === self.statusItems[.awake]?.button?.window else { return }
                    self.updateAwakeIcon()
                }
            }
        ]
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screensAsleep = asleep
                    self?.updateAwakeIcon()
                    self?.updateCloudIcon()
                }
            })
        }
        trackAwake()
        trackCloud()
        refresh()
    }

    func stop() {
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        stopPulse()
        stopCloudDraw()
        popovers.values.forEach { $0.performClose(nil) }
        popovers.removeAll()
        statusItems.values.forEach(NSStatusBar.system.removeStatusItem)
        statusItems.removeAll()
    }

    func refresh() {
        let desired = IndividualMenuBarTool.allCases.filter {
            $0.usesMenuBarMode(
                .separate,
                enabled: SettingsManager.shared.isToolEnabled($0.id),
                in: defaults
            )
        }
        let plan = IndividualMenuBarRefreshPlan(current: Set(statusItems.keys), desired: desired)
        for tool in plan.insertions {
            statusItems[tool] = makeStatusItem(for: tool)
        }
        for tool in plan.removals {
            popovers.removeValue(forKey: tool)?.performClose(nil)
            if let item = statusItems.removeValue(forKey: tool) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
        updateAwakeIcon()
        updateCloudIcon()
    }

    private func trackCloud() {
        withObservationTracking { _ = RcloneJobManager.shared.jobs.map(\.state) } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.observers.isEmpty else { return }
                self.updateCloudIcon()
                self.trackCloud()
            }
        }
    }

    private func cloudActivity() -> MenuBarAttentionBudget.Activity {
        let manager = RcloneJobManager.shared
        let moving = manager.jobs.filter { $0.state.isActive && $0.state != .paused }
        if !moving.isEmpty { return .running(eta: moving.compactMap(\.displayEta).max()) }
        if manager.jobs.contains(where: { $0.state == .paused }) { return .paused }
        return manager.hasUnseenFailure ? .failed : .idle
    }

    /// RSync UI's cloud draws and erases only inside the attention budget's play window (DESIGN.md "Motion").
    private func updateCloudIcon() {
        cloudTimer?.invalidate()
        cloudTimer = nil
        let motion = animates(.cloudSync) && !screensAsleep && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let glyph = cloudBudget.update(cloudActivity(), now: Date(), motionAllowed: motion)
        guard let button = statusItems[.cloudSync]?.button else { return stopCloudDraw() }
        switch glyph {
        case .idle, .working:
            stopCloudDraw()
            button.image = StatusItemIcon.glyph("MenuBarGlyphCloud")
        case .error:
            stopCloudDraw()
            button.image = StatusItemIcon.glyph("MenuBarGlyphCloudError")
        case .animating:
            if cloudDraw == nil { startCloudDraw(in: button, loop: true) }
            if let end = cloudBudget.windowEnd, end != .distantFuture {
                cloudTimer = Timer.scheduledTimer(withTimeInterval: end.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateCloudIcon() }
                }
            }
        case .finishing:
            startCloudDraw(in: button, loop: false)
            cloudTimer = Timer.scheduledTimer(withTimeInterval: Self.cloudCycle / 2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCloudIcon() }
            }
        }
    }

    private static let cloudCycle: CFTimeInterval = 3.2

    /// The cloud outline revealed by a stroked mask on the glyph's own path: strokeEnd draws it, strokeStart
    /// erases it. Masking the template image keeps the menu bar's own tint.
    private func startCloudDraw(in button: NSStatusBarButton, loop: Bool) {
        stopCloudDraw()
        guard let cloud = StatusItemIcon.glyph("MenuBarGlyphCloud") else { return }
        button.image = NSImage(size: cloud.size, flipped: false) { _ in true }
        button.image?.isTemplate = true
        button.wantsLayer = true
        let view = NSImageView(image: cloud)
        view.imageScaling = .scaleNone
        view.frame = button.bounds
        view.wantsLayer = true
        let origin = CGPoint(x: (button.bounds.width - cloud.size.width) / 2, y: (button.bounds.height - cloud.size.height) / 2)
        let mask = CAShapeLayer()
        mask.frame = view.bounds
        mask.path = Self.cloudPath(origin: origin, height: cloud.size.height)
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineWidth = 2.4
        mask.lineCap = .round
        mask.lineJoin = .round
        mask.strokeEnd = loop ? 0 : 1
        view.layer?.mask = mask
        button.addSubview(view)
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        if loop {
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 1, 1]
            draw.keyTimes = [0, 0.5, 1]
            draw.timingFunctions = [ease, ease]
            let erase = CAKeyframeAnimation(keyPath: "strokeStart")
            erase.values = [0, 0, 1]
            erase.keyTimes = [0, 0.5, 1]
            erase.timingFunctions = [ease, ease]
            let group = CAAnimationGroup()
            group.animations = [draw, erase]
            group.duration = Self.cloudCycle
            group.repeatCount = .infinity
            mask.add(group, forKey: "draw")
        } else {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = Self.cloudCycle / 2
            draw.timingFunction = ease
            mask.add(draw, forKey: "draw")
        }
        cloudDraw = view
    }

    /// `MenuBarGlyphCloud.svg`'s path (SVG units, y down) placed in the layer (y up).
    private static func cloudPath(origin: CGPoint, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4.5, y: 12.75))
        path.addLine(to: CGPoint(x: 11.5, y: 12.75))
        path.addArc(center: CGPoint(x: 11.5, y: 9.75), radius: 3, startAngle: .pi / 2, endAngle: -1.370, clockwise: true)
        path.addArc(center: CGPoint(x: 8.059, y: 9.008), radius: 4.6, startAngle: -0.4975, endAngle: -2.9429, clockwise: true)
        path.addArc(center: CGPoint(x: 4.377, y: 10.353), radius: 2.4, startAngle: -1.9234, endAngle: -4.7631, clockwise: true)
        var transform = CGAffineTransform(translationX: origin.x - 0.7, y: origin.y + height + 1.35).scaledBy(x: 1, y: -1)
        return path.copy(using: &transform) ?? path
    }

    private func stopCloudDraw() {
        cloudDraw?.removeFromSuperview()
        cloudDraw = nil
    }

    private func trackAwake() {
        withObservationTracking { _ = AwakeService.shared.isActive } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.observers.isEmpty else { return }
                self.updateAwakeIcon()
                self.trackAwake()
            }
        }
    }

    private func animates(_ tool: IndividualMenuBarTool) -> Bool {
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        guard let key = tool.animationPreferenceKey else { return false }
        return flag(Self.animatedIconsKey) && flag(key)
    }

    /// Open eye with rays (or cup with steam) while Awake holds the Mac awake, closed eye (or plain cup)
    /// otherwise. The pulse runs only while it is on, motion is on, and the status item is on screen.
    private func updateAwakeIcon() {
        guard let button = statusItems[.awake]?.button else { return stopPulse() }
        let tool = IndividualMenuBarTool.awake
        let style = AwakeMenuBarStyle(rawValue: defaults.string(forKey: AwakeMenuBarStyle.key) ?? "") ?? .eye
        guard AwakeService.shared.isActive else {
            stopPulse()
            button.image = StatusItemIcon.glyph(style.off)
            return
        }
        let visible = !screensAsleep && button.window?.occlusionState.contains(.visible) ?? false
        guard animates(tool), visible else {
            stopPulse()
            button.image = StatusItemIcon.glyph(style.on, accent: style.accent, opacity: 1)
            return
        }
        guard pulseRays == nil || pulseStyle != style else { return }
        stopPulse()
        button.image = StatusItemIcon.glyph(style.on)
        button.wantsLayer = true
        let rays = NSImageView(image: StatusItemIcon.glyph(style.accent) ?? NSImage())
        rays.imageScaling = .scaleNone
        rays.frame = button.bounds
        rays.autoresizingMask = [.width, .height]
        rays.wantsLayer = true
        button.addSubview(rays)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.3
        pulse.duration = 1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rays.layer?.add(pulse, forKey: "pulse")
        pulseRays = rays
        pulseStyle = style
    }

    private func stopPulse() {
        pulseRays?.removeFromSuperview()
        pulseRays = nil
    }

    private func makeStatusItem(for tool: IndividualMenuBarTool) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = tool.autosaveName
        guard let button = item.button else { return item }

        button.image = StatusItemIcon.glyph(tool.menuBarGlyph)
        button.imagePosition = .imageOnly
        button.identifier = NSUserInterfaceItemIdentifier("individual-menu.\(tool.id)")
        button.setAccessibilityIdentifier("individual-menu.\(tool.id)")
        button.setAccessibilityLabel(tool.title)
        button.target = self
        button.action = #selector(activate(_:))
        button.sendAction(on: [.leftMouseDown])
        button.toolTip = tool.title
        return item
    }

    @objc private func activate(_ sender: NSStatusBarButton) {
        guard let identifier = sender.identifier?.rawValue,
              let tool = IndividualMenuBarTool.allCases.first(where: {
                  identifier == "individual-menu.\($0.id)"
              }) else { return }

        let controlClick = NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if case .execute(let action) = tool.activation, !controlClick {
            popovers[tool]?.performClose(nil)
            OnePlusPanelTimings.shared.cancel(panel: tool.id)
            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
        } else if let popover = popovers[tool], popover.isShown {
            popover.performClose(nil)
            OnePlusPanelTimings.shared.cancel(panel: tool.id)
        } else {
            show(tool: tool)
        }
    }

    /// Right click on a one-action item opens its panel; other items keep the app menu.
    func handleSecondaryClick(on button: NSStatusBarButton) -> Bool {
        guard let tool = statusItems.first(where: { $0.value.button === button })?.key,
              case .execute = tool.activation else { return false }
        show(tool: tool)
        return true
    }

    func show(tool: IndividualMenuBarTool, diagnostic: Bool = false) {
        guard let button = statusItems[tool]?.button else { return }
        MenuPanelRelease.shared.cancel(tool.id)
        if diagnostic {
            OnePlusPanelTimings.shared.begin(panel: tool.id, tab: tool.id, input: "diagnostics")
        } else { OnePlusPanelTimings.shared.beginOpenIfNeeded(panel: tool.id) }
        let ceiling = (button.window?.screen?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction
        let popover = popovers[tool] ?? makePopover(for: tool, maximumHeight: ceiling)
        popovers[tool] = popover
        guard let host = popover.contentViewController as? NSHostingController<AnyView> else { return }
        host.rootView = content(for: tool, maximumHeight: ceiling, popover: popover)
        host.view.frame.size.width = OnePlusMenuMetrics.width
        let size = NSSize(width: OnePlusMenuMetrics.width, height: min(host.view.fittingSize.height, ceiling))
        host.view.setFrameSize(size)
        host.view.layoutSubtreeIfNeeded()
        popover.contentSize = size
        if diagnostic {
            popover.showInBackground(relativeTo: button.bounds, of: button)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func makePopover(for tool: IndividualMenuBarTool, maximumHeight: CGFloat) -> OnePlusMenuPresenter {
        let popover = OnePlusMenuPresenter()
        popover.contentViewController = NSHostingController(rootView: content(for: tool, maximumHeight: maximumHeight, popover: popover))
        popover.onClose = { [weak self, weak popover] in
            MenuPanelRelease.shared.schedule(tool.id) { [weak self, weak popover] in
                guard let self, let popover, !popover.isShown, self.popovers[tool] === popover else { return }
                self.popovers[tool] = nil
            }
        }
        return popover
    }

    private func content(for tool: IndividualMenuBarTool, maximumHeight: CGFloat, popover: OnePlusMenuPresenter) -> AnyView {
        AnyView(IndividualToolMenuPanel(tool: tool)
            .environment(\.onePlusMenuMaximumHeight, maximumHeight)
            .onOnePlusMenuHeightChange { [weak popover] height in
                let size = NSSize(width: OnePlusMenuMetrics.width, height: height)
                if popover?.contentSize != size { popover?.contentSize = size }
            })
    }
}

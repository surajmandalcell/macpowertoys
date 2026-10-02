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
        case .cloudSync: "Cloud Sync"
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

    var quickAction: ToolActionID? {
        switch self {
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

@MainActor
final class IndividualMenuBarController: NSObject {
    static let shared = IndividualMenuBarController()
    static weak var current: IndividualMenuBarController?

    private let defaults = UserDefaults.standard
    private var statusItems: [IndividualMenuBarTool: NSStatusItem] = [:]
    private var popovers: [IndividualMenuBarTool: OnePlusMenuPresenter] = [:]
    private var observers: [NSObjectProtocol] = []

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
            }
        ]
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
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
    }

    private func makeStatusItem(for tool: IndividualMenuBarTool) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = tool.autosaveName
        guard let button = item.button else { return item }

        let image = StatusItemIcon.symbol(tool.symbol)
        button.image = image
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

        if let popover = popovers[tool], popover.isShown {
            popover.performClose(nil)
            OnePlusPanelTimings.shared.cancel(panel: tool.id)
        } else {
            show(tool: tool)
        }
    }

    func show(tool: IndividualMenuBarTool, diagnostic: Bool = false) {
        guard let button = statusItems[tool]?.button else { return }
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

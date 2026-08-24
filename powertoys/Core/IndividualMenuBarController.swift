import AppKit
import Foundation

enum IndividualMenuBarTool: String, CaseIterable, Identifiable {
    case cloudSync = "rclone"
    case awake
    case colorPicker = "color-picker"
    case textExtractor = "text-extractor"
    case inputDevices = "input-devices"

    var id: String { rawValue }
    var preferenceKey: String { "tool.\(rawValue).showMenuBarIcon" }
    var autosaveName: String { "MacPowerToys.\(rawValue)" }

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
        case .cloudSync: "arrow.up.arrow.down.circle"
        case .awake: "cup.and.saucer"
        case .colorPicker: "eyedropper"
        case .textExtractor: "text.viewfinder"
        case .inputDevices: "computermouse"
        }
    }

    var quickAction: ToolActionID? {
        switch self {
        case .colorPicker: .colorPickerPick
        case .textExtractor: .textExtractorCapture
        default: nil
        }
    }
}

@MainActor
final class IndividualMenuBarController: NSObject {
    static let shared = IndividualMenuBarController()

    private let defaults = UserDefaults.standard
    private var statusItems: [IndividualMenuBarTool: NSStatusItem] = [:]
    private var observers: [NSObjectProtocol] = []

    private override init() {}

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
        statusItems.values.forEach(NSStatusBar.system.removeStatusItem)
        statusItems.removeAll()
    }

    func refresh() {
        for tool in IndividualMenuBarTool.allCases {
            let shouldShow = defaults.bool(forKey: tool.preferenceKey)
                && SettingsManager.shared.isToolEnabled(tool.id)
            if shouldShow, statusItems[tool] == nil {
                statusItems[tool] = makeStatusItem(for: tool)
            } else if !shouldShow, let item = statusItems.removeValue(forKey: tool) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
    }

    private func makeStatusItem(for tool: IndividualMenuBarTool) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = tool.autosaveName
        guard let button = item.button else { return item }

        let image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.identifier = NSUserInterfaceItemIdentifier("individual-menu.\(tool.id)")
        button.target = self
        button.action = #selector(activate(_:))
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = tool.quickAction == nil ? "Open \(tool.title)" : tool.title
        return item
    }

    @objc private func activate(_ sender: NSStatusBarButton) {
        guard let identifier = sender.identifier?.rawValue,
              let tool = IndividualMenuBarTool.allCases.first(where: {
                  identifier == "individual-menu.\($0.id)"
              }) else { return }

        if let action = tool.quickAction {
            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
        } else {
            ToolActionRouter.shared.open(toolID: tool.id)
        }
    }
}

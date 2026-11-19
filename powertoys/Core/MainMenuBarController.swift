import AppKit
import OnePlusUI
import SwiftUI

@MainActor
final class MainMenuBarController: NSObject {
    static let shared = MainMenuBarController()
    private var item: NSStatusItem?
    private let panel = OnePlusMenuPresenter()
    private var content: (() -> AnyView)?
    private var hosting: NSHostingController<AnyView>?
    private var maximumHeight: CGFloat?

    override init() {
        super.init()
        panel.onClose = { [weak self] in self?.panelDidClose() }
    }

    private func panelDidClose() {
        MenuPanelTopProcesses.shared.scheduleRelease()
        // The selected tab lives in AppStorage, so the released tree reopens on the same tab.
        MenuPanelRelease.shared.schedule("main") { [weak self] in
            guard let self, !self.panel.isShown else { return }
            self.panel.contentViewController = nil
            self.hosting = nil
            self.maximumHeight = nil
        }
    }

    func configure(isInserted: Bool, content: @escaping () -> AnyView) {
        self.content = content
        guard isInserted else {
            panel.close()
            panel.contentViewController = nil
            hosting = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MacPowerToys"
        item.button?.image = StatusItemIcon.main
        item.button?.identifier = .init("MenuBarIcon")
        item.button?.setAccessibilityIdentifier("MenuBarIcon")
        item.button?.setAccessibilityLabel("MacPowerToys")
        item.button?.toolTip = "MacPowerToys"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseDown])
        self.item = item
    }

    func closePanel() {
        panel.close()
    }

    @objc private func toggle() {
        if panel.isShown {
            panel.close()
            OnePlusPanelTimings.shared.cancel(panel: "main")
            return
        }
        guard let button = item?.button, let content else { return }
        MenuPanelRelease.shared.cancel("main")
        OnePlusPanelTimings.shared.beginOpenIfNeeded(panel: "main")
        let ceiling = (button.window?.screen?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction
        if hosting == nil || maximumHeight != ceiling {
            // The panel root has a fixed natural height, so its geometry is the panel's content height.
            let root = AnyView(content().environment(\.onePlusMenuMaximumHeight, ceiling)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak panel] height in
                    guard height > 0 else { return }
                    panel?.contentSize = NSSize(width: OnePlusMenuMetrics.width, height: height)
                })
            if let hosting { hosting.rootView = root }
            else { hosting = NSHostingController(rootView: root) }
            maximumHeight = ceiling
        }
        guard let hosting else { return }
        let size = hosting.sizeThatFits(in: NSSize(width: OnePlusMenuMetrics.width, height: ceiling))
        hosting.view.setFrameSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        panel.contentViewController = hosting
        panel.contentSize = size
        DiagnosticsMenuPanels.shared.mainWindow = hosting.view.window
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

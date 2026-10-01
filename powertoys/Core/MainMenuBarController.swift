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

    @objc private func toggle() {
        if panel.isShown {
            panel.close()
            OnePlusPanelTimings.shared.cancel(panel: "main")
            return
        }
        guard let button = item?.button, let content else { return }
        OnePlusPanelTimings.shared.beginOpenIfNeeded(panel: "main")
        let ceiling = (button.window?.screen?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction
        if hosting == nil || maximumHeight != ceiling {
            let root = AnyView(content().environment(\.onePlusMenuMaximumHeight, ceiling)
                .onOnePlusMenuHeightChange { [weak panel] height in
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

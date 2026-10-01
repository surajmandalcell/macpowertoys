import AppKit
import OnePlusUI

nonisolated enum SystemMonitorFreshness {
    static func allowance(interval: TimeInterval) -> TimeInterval { max(interval * 3, 3) }
    static let staleHelp = "Stale reading. Showing the last successful sample."
}

@MainActor
enum SystemMonitorStatusText {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    static let groupGap = width(of: "  ")
    private static let iconGap = width(of: " ")

    static func value(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font])
    }

    static func width(of text: String) -> CGFloat { value(text).size().width }

    static func width(for item: SystemMonitorMenuItemConfiguration) -> CGFloat {
        item.style == .iconOnly ? 0 : ceil(SystemMonitorMenuRenderer.widthCandidates(for: item).map(width(of:)).max() ?? 0)
    }

    static func contentWidth(for style: SystemMonitorMenuItemStyle, valueWidth: CGFloat) -> CGFloat {
        switch style {
        case .iconOnly: OnePlusMenuMetrics.statusIconSize
        case .valueOnly: valueWidth
        case .iconAndValue: OnePlusMenuMetrics.statusIconSize + iconGap + valueWidth
        }
    }

    static func length(for items: [SystemMonitorMenuItemConfiguration], widths: [SystemMonitorMenuMetric: CGFloat]) -> CGFloat {
        let content = items.reduce(CGFloat.zero) { $0 + contentWidth(for: $1.style, valueWidth: widths[$1.metric] ?? 0) }
        // The native square reserves the status button's normal horizontal margins.
        let margins = max(NSStatusBar.system.thickness - OnePlusMenuMetrics.statusIconSize, 0)
        return ceil(content + CGFloat(max(items.count - 1, 0)) * groupGap + margins)
    }
}

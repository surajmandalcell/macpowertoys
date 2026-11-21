import OnePlusUI
import SwiftUI

/// One thing that needs the owner, with the click that fixes it.
struct AttentionItem: Identifiable {
    let id: String
    let title: String
    let line: String
    let fix: () -> Void

    @MainActor static var current: [AttentionItem] {
        var items: [AttentionItem] = []
        if InputDevicesManager.shared.wantsScrollTap, let problem = PermissionCenter.shared.accessibilityProblem {
            items.append(AttentionItem(id: "accessibility", title: "Scrolling is off", line: problem) {
                InputDevicesManager.shared.fixAccessibility()
            })
        }
        let saved = FanControlService.savedPreset
        if saved != .auto, FanHelperService.shared.canInstall {
            items.append(AttentionItem(id: "fan-saved", title: "Fans stay on Auto",
                                       line: "\(saved.rawValue) needs the fan helper. Click Fix to install it; macOS asks for your password.") {
                Task {
                    if await FanHelperService.shared.install() == nil { await FanControlService.shared.restoreSavedPreset() }
                }
            })
        }
        if FanHelperService.shared.status == .notResponding {
            items.append(AttentionItem(id: "fan-helper", title: "Fan helper is not responding",
                                       line: "Fans stay read only. Click Fix to reinstall the helper; macOS asks for your password.") {
                Task { _ = await FanHelperService.shared.install() }
            })
        }
        return items
    }
}

/// The header bell left of Settings (DESIGN.md "Attention bell"): a red dot while an item needs attention, and a
/// popover with one plain line and a Fix key per item.
struct AttentionBell: View {
    @State private var isOpen = false
    // shortcut: dot size and inset live here, not in OnePlusUI; move them there when a second badge appears.
    private static let dotSize: CGFloat = 7
    private static let dotInset: CGFloat = 4
    static let listWidth: CGFloat = 312
    static let openNotification = Notification.Name("AttentionBell.open")
    /// Set by the diagnostics link `popover/attention?sample`: adds a no-op item so a focus check has a Fix key.
    static var diagnosticSample = false
    private static let sampleItem = AttentionItem(id: "sample", title: "Sample item",
                                                  line: "Diagnostics preview. Fix does nothing.") {}

    var body: some View {
        let items = AttentionItem.current + (Self.diagnosticSample ? [Self.sampleItem] : [])
        OnePlusLinearIconButton(systemImage: "bell",
                                help: items.isEmpty ? "Nothing needs attention" : "\(items.count) need attention",
                                size: OnePlusLinearMetrics.iconTab) {
            isOpen.toggle()
        }
        .overlay(alignment: .topTrailing) {
            if !items.isEmpty {
                Circle().fill(OnePlusLinearColor.destructiveText).frame(width: Self.dotSize, height: Self.dotSize)
                    .offset(x: -Self.dotInset, y: Self.dotInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("panel.attention")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            AttentionList(items: items) { isOpen = false }.onePlusFocusPolicy()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.openNotification)) { _ in isOpen = true }
        .onChange(of: isOpen) { if !isOpen { Self.diagnosticSample = false } }
    }
}

private struct AttentionList: View {
    let items: [AttentionItem]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletRowGap) {
            Text(items.isEmpty ? "Nothing needs your attention." : "Needs attention")
                .linearText(OnePlusLinearMetrics.caption, weight: .semibold, color: OnePlusLinearColor.secondary)
            ForEach(items) { item in
                OnePlusLinearBanner(.warning, title: item.title, message: item.line) {
                    Button("Fix") {
                        close()
                        item.fix()
                    }
                    .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OnePlusLinearMetrics.appletRowPadding)
        .frame(width: AttentionBell.listWidth)
    }
}

import SwiftUI

public struct OnePlusAppletTitlebar<Title: View, Actions: View>: View {
    let title: Title
    let actions: Actions
    let clearsTrafficLights: Bool
    private var titleText = ""
    @Environment(\.onePlusZoomTrailingX) private var zoomTrailingX
    @Environment(\.displayScale) private var displayScale
    public init(clearsTrafficLights: Bool = true, @ViewBuilder title: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.clearsTrafficLights = clearsTrafficLights; self.title = title(); self.actions = actions()
    }
    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            OnePlusHeaderTitleLayout(text: titleText, pointSize: OnePlusTextRole.sidebarTitle.size(for: .regular),
                                     height: 24, scale: displayScale) {
                title.onePlusText(.sidebarTitle).lineLimit(1)
            }
            Spacer(minLength: 12)
            actions
        }
        .frame(height: 24, alignment: .top).padding(.top, OnePlusMetrics.contentTop)
        .padding(.leading, clearsTrafficLights ? OnePlusMetrics.titleStart(afterZoom: zoomTrailingX) : 16)
        .padding(.trailing, 16).frame(height: OnePlusMetrics.appletTitlebar)
        .background(OnePlusWindowDragArea())
        .environment(\.onePlusHeaderTopAligned, true)
    }
}

public extension OnePlusAppletTitlebar where Title == Text {
    init(title: String, @ViewBuilder actions: () -> Actions) {
        self.init(title: { Text(title) }, actions: actions)
        titleText = title
    }
}

public struct OnePlusFloatingSettingsButton: View {
    let active: Bool
    let label: String
    let action: () -> Void
    @Environment(\.onePlusTimingWindow) private var timingWindow
    public init(isActive: Bool, help: String? = nil, action: @escaping () -> Void) {
        active = isActive; label = help ?? (isActive ? "Back to home" : "Settings"); self.action = action
    }
    public var body: some View {
        Button {
            if !timingWindow.isEmpty {
                OnePlusPanelTimings.shared.begin(panel: timingWindow, operation: .pageSwitch,
                                                tab: active ? "content" : "settings", input: "settings-button")
            }
            action()
        } label: {
            Image(systemName: active ? "gearshape.fill" : "gearshape")
                .font(.system(size: 12)).foregroundStyle(OnePlusColor.secondary)
                .frame(width: 24, height: 24)
                .background(active ? OnePlusColor.selection : OnePlusColor.raised, in: Circle())
        }
        .buttonStyle(OnePlusInteractionStyle(selected: active, radius: 12))
        .help(label).accessibilityLabel(label)
    }
}

public extension View {
    /// Apply to the applet body before an existing bottom-trailing gear overlay.
    func onePlusFloatingSettingsInset() -> some View {
        padding(.bottom, OnePlusMetrics.floatingSettingsInset)
    }

    /// Reserves the gear's area and places it at the shared eight-point inset.
    func onePlusFloatingSettings(isActive: Bool, help: String? = nil,
                                action: @escaping () -> Void) -> some View {
        onePlusFloatingSettingsInset().overlay(alignment: .bottomTrailing) {
            OnePlusFloatingSettingsButton(isActive: isActive, help: help, action: action).padding(8)
        }
    }
}

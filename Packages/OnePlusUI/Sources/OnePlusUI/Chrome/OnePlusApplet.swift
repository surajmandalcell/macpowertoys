import SwiftUI

public struct OnePlusAppletTitlebar<Title: View, Actions: View>: View {
    let title: Title
    let actions: Actions
    let clearsTrafficLights: Bool
    @Environment(\.onePlusZoomTrailingX) private var zoomTrailingX
    public init(clearsTrafficLights: Bool = true, @ViewBuilder title: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.clearsTrafficLights = clearsTrafficLights; self.title = title(); self.actions = actions()
    }
    public var body: some View {
        HStack(spacing: 8) {
            title.onePlusText(.sidebarTitle).lineLimit(1)
            Spacer(minLength: 12)
            actions
        }
        .frame(height: 24).padding(.top, 4)
        .padding(.leading, clearsTrafficLights ? OnePlusMetrics.titleStart(afterZoom: zoomTrailingX) : 16)
        .padding(.trailing, 16).frame(height: 40)
        .background(OnePlusWindowDragArea())
    }
}

public extension OnePlusAppletTitlebar where Title == Text {
    init(title: String, @ViewBuilder actions: () -> Actions) {
        self.init(title: { Text(title) }, actions: actions)
    }
}

public struct OnePlusFloatingSettingsButton: View {
    let active: Bool
    let label: String
    let action: () -> Void
    public init(isActive: Bool, help: String? = nil, action: @escaping () -> Void) {
        active = isActive; label = help ?? (isActive ? "Back to home" : "Settings"); self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: active ? "gearshape.fill" : "gearshape")
                .font(.system(size: 12)).foregroundStyle(OnePlusColor.secondary)
                .frame(width: 24, height: 24)
                .background(active ? OnePlusColor.selection : OnePlusColor.raised, in: Circle())
        }
        .buttonStyle(OnePlusInteractionStyle(selected: active, radius: 12))
        .help(label).accessibilityLabel(label)
    }
}

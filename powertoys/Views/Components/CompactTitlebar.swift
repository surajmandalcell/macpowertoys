import OnePlusUI
import SwiftUI

struct CompactTitlebar<Title: View, Actions: View>: View {
    let clearsTrafficLights: Bool
    let title: Title
    let actions: Actions
    init(clearsTrafficLights: Bool = true, @ViewBuilder title: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.clearsTrafficLights = clearsTrafficLights; self.title = title(); self.actions = actions()
    }
    var body: some View {
        OnePlusAppletTitlebar(clearsTrafficLights: clearsTrafficLights, title: { title }, actions: { actions })
    }
}

struct CompactTitlebarTitle: View {
    let title: String
    var body: some View { Text(title).onePlusText(.sidebarTitle).lineLimit(1) }
}

struct CompactTitlebarButton: View {
    let title: String
    var isPrimary = false
    let action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(OnePlusButtonStyle(isPrimary ? .primary : .ghost, size: .small))
    }
}

struct CompactTitlebarControlLabel<Content: View>: View {
    let isPrimary: Bool
    let foregroundStyle: AnyShapeStyle?
    let content: Content
    init(isPrimary: Bool = false, foregroundStyle: AnyShapeStyle? = nil, @ViewBuilder content: () -> Content) {
        self.isPrimary = isPrimary; self.foregroundStyle = foregroundStyle; self.content = content()
    }
    var body: some View {
        OnePlusControlLabel(variant: isPrimary ? .primary : .ghost, size: .small) { content }
    }
}

import OnePlusUI
import SwiftUI

struct WorkspacePage<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    private let fillsAvailableHeight: Bool
    private let actions: Actions
    private let content: Content
    init(_ title: String, subtitle: String? = nil, fillsAvailableHeight: Bool = false,
         @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.fillsAvailableHeight = fillsAvailableHeight
        self.actions = actions(); self.content = content()
    }
    var body: some View {
        OnePlusPage(scrolls: !fillsAvailableHeight) {
            OnePlusPageHeader(title: title, subtitle: subtitle) { actions }
        } content: { content }
    }
}

extension WorkspacePage where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, actions: { EmptyView() }, content: content)
    }
}

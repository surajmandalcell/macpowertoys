import OnePlusUI
import SwiftUI

/// A fixed RSync UI page on the v15 pane gutters, for pages whose table or list scrolls inside the page.
struct RSyncFixedPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionGap) { content }
            .padding(.top, OnePlusLinearMetrics.bodyTop)
            .padding(.horizontal, OnePlusLinearMetrics.gutter)
            .padding(.bottom, OnePlusLinearMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A page toolbar on the page itself: leading context, then trailing actions, on one line.
/// A filled settings group, captioned when it has a title (pages) and bare when its host shows the title (setup steps).
struct RSyncGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        if let title {
            OnePlusLinearAppletSection(title) { content }
        } else {
            OnePlusLinearAppletGroup { content }
        }
    }
}

/// A switch row in a filled group.
struct RSyncSwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title; self.detail = detail; _isOn = isOn
    }

    var body: some View {
        OnePlusLinearAppletRow(title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
        }
    }
}

enum RSyncPaneMetrics {
    /// The owner's minimum search width when the bar has room.
    static let searchWidth: CGFloat = 300
}

struct RSyncPageToolbar<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
            leading
            Spacer(minLength: OnePlusLinearMetrics.appletActionGap)
            trailing
        }
        .frame(height: OnePlusLinearMetrics.button)
    }
}

import OnePlusUI
import SwiftUI

extension OnePlusWindowCanvas {
    /// The v15 form of a sidebar tool window: the same size, the Linear sidebar, and the lights on the 44 pt toolbar centerline.
    // shortcut: `isApplet` is the only 1.2.1 way to center the lights on C = 22; use a v15 canvas flag when OnePlusUI adds one.
    var linear: Self { Self(width: size.width, height: size.height, sidebarWidth: OnePlusLinearMetrics.sidebarWidth, density: density, isApplet: true) }
}

/// A v15 sidebar tool window: the Linear sidebar and one pane on the window surface, no texture,
/// the Quiet Raised control look, and Quiet motion.
struct LinearToolWindow<Sidebar: View, Content: View>: View {
    let canvas: OnePlusWindowCanvas
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(maxHeight: .infinity).clipped()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }
        .background(OnePlusLinearColor.window)
        .ignoresSafeArea()
        .onePlusFixedCanvas(canvas.linear)
        .onePlusNeutralControls()
        .environment(\.onePlusLinearControlLook, .quietRaised)
        .onePlusLinearMotion(.quiet)
    }
}

/// The v15 pane: the 44 pt toolbar with back, forward, the page title, and trailing actions, then the page.
/// Back and forward walk the pages this window showed.
struct LinearToolPane<Page: Hashable, Trailing: View, Content: View>: View {
    @Binding var page: Page
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content
    @State private var back: [Page] = []
    @State private var forward: [Page] = []
    @State private var traversing = false

    init(page: Binding<Page>, title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        _page = page; self.title = title; self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            OnePlusLinearPaneToolbar(title: title, canGoBack: !back.isEmpty, canGoForward: !forward.isEmpty,
                                     back: goBack, forward: goForward) {
                HStack(spacing: OnePlusLinearMetrics.appletActionGap) { trailing }
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: page) { old, _ in
            if traversing { traversing = false; return }
            back.append(old)
            if back.count > MainPageHistory.limit { back.removeFirst() }
            forward.removeAll()
        }
    }

    private func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(page)
        traversing = true
        page = previous
    }

    private func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(page)
        traversing = true
        page = next
    }
}

/// Quiet status or metadata text for a pane toolbar or a group row.
struct LinearCaption: View {
    let text: String
    var monospaced = false

    init(_ text: String, monospaced: Bool = false) { self.text = text; self.monospaced = monospaced }

    var body: some View {
        label.lineLimit(1).truncationMode(.middle).help(text)
    }

    @ViewBuilder private var label: some View {
        if monospaced {
            Text(text).font(.system(size: OnePlusLinearMetrics.control, design: .monospaced)).foregroundStyle(OnePlusLinearColor.muted)
        } else {
            Text(text).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.muted)
        }
    }
}

/// A fixed row under a pane body, such as the Scroll device row, on the pane gutter.
struct LinearPaneFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, OnePlusLinearMetrics.gutter)
            .padding(.top, OnePlusLinearMetrics.sectionGap / 2)
            .padding(.bottom, OnePlusLinearMetrics.gutter)
    }
}

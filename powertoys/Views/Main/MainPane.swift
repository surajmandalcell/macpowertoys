import SwiftUI
import OnePlusUI

// ponytail: main-window geometry lives in the app until the next OnePlusUI tag; then move it to OnePlusMetrics and OnePlusWindowCanvas.main.
enum MainPaneMetrics {
    static let sidebarIcon: CGFloat = 20
    static let rowIcon: CGFloat = 24
    static let heroIcon: CGFloat = 48
    static let gutter: CGFloat = 20
    static let sectionGap: CGFloat = 10
    static let sectionTitleGap: CGFloat = 6
    static let sectionTitleInset: CGFloat = 10
    static let sidebarGroupGap: CGFloat = 12
    static let sidebarRowInset: CGFloat = 8
    static let iconGap: CGFloat = 8
    static let toolbarInset: CGFloat = 12
    static let heroPadding: CGFloat = 20
    static let segmentedWidth: CGFloat = 300
}

extension OnePlusWindowCanvas {
    static let mainWindow = Self(width: 820, height: 660, sidebarWidth: 215)
}

struct MainPageHistory: Equatable {
    static let limit = 50
    private(set) var back: [String] = []
    private(set) var forward: [String] = []

    mutating func record(from old: String, to new: String) {
        guard old != new else { return }
        back.append(old)
        if back.count > Self.limit { back.removeFirst() }
        forward.removeAll()
    }

    mutating func goBack(from current: String) -> String? {
        guard let page = back.popLast() else { return nil }
        forward.append(current)
        return page
    }

    mutating func goForward(from current: String) -> String? {
        guard let page = forward.popLast() else { return nil }
        back.append(current)
        return page
    }
}

/// System Settings structure: a flat sidebar and a pane with one toolbar row.
struct MainWindowShell<Sidebar: View, Content: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: OnePlusWindowCanvas.mainWindow.sidebarWidth).frame(maxHeight: .infinity)
                .background(OnePlusColor.sidebar)
                .overlay(alignment: .trailing) { OnePlusColor.line.frame(width: 1) }
                .clipped()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }
        .background(OnePlusColor.window)
        .ignoresSafeArea()
        .onePlusFixedCanvas(.mainWindow)
        .onePlusNeutralControls()
    }
}

struct MainPaneToolbar: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let back: () -> Void
    let forward: () -> Void

    var body: some View {
        HStack(spacing: MainPaneMetrics.toolbarInset) {
            HStack(spacing: 0) {
                navigationButton("chevron.left", "Back", enabled: canGoBack, action: back)
                OnePlusColor.line.frame(width: 1, height: OnePlusMetrics.compactControlHeight / 2)
                navigationButton("chevron.right", "Forward", enabled: canGoForward, action: forward)
            }
            .background(OnePlusColor.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(OnePlusColor.line, lineWidth: 1) }
            Text(title).onePlusText(.sectionTitle).lineLimit(1).help(title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MainPaneMetrics.toolbarInset)
        .frame(height: OnePlusMetrics.titleRow)
        .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
        .accessibilityIdentifier("main.toolbar")
    }

    private func navigationButton(_ symbol: String, _ label: String, enabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(OnePlusButtonStyle(.icon))
            .disabled(!enabled)
            .help(label).accessibilityLabel(label)
    }
}

/// The scrolling body of a pane. Sections stack with Settings rhythm on one gutter.
struct MainPaneScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MainPaneMetrics.sectionGap) { content }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, MainPaneMetrics.gutter)
                .padding(.bottom, MainPaneMetrics.gutter)
        }
        .onePlusScrollIndicators(axes: .vertical)
    }
}

/// A Settings section: an optional title outside one rounded group of rows.
struct MainSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MainPaneMetrics.sectionTitleGap) {
            if let title {
                Text(title).onePlusText(.sectionTitle).accessibilityAddTraits(.isHeader)
                    .padding(.leading, MainPaneMetrics.sectionTitleInset)
                    .padding(.top, MainPaneMetrics.sectionGap)
            }
            OnePlusCard { content }
        }
    }
}

/// The centered identity block at the top of a pane.
struct MainHero<Icon: View, Controls: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let controls: Controls

    var body: some View {
        OnePlusCard {
            VStack(spacing: MainPaneMetrics.sectionTitleGap) {
                icon.frame(width: MainPaneMetrics.heroIcon, height: MainPaneMetrics.heroIcon)
                    .accessibilityHidden(true)
                Text(title).onePlusText(.pageTitle).lineLimit(1).help(title)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).onePlusText(.subtitle).multilineTextAlignment(.center)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).help(subtitle)
                controls.padding(.top, MainPaneMetrics.sectionTitleGap)
            }
            .frame(maxWidth: .infinity)
            .padding(MainPaneMetrics.heroPadding)
        }
    }
}

struct MainSidebarRow<Icon: View>: View {
    let title: String
    var selected = false
    var muted = false
    @ViewBuilder let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MainPaneMetrics.iconGap) {
                icon.frame(width: MainPaneMetrics.sidebarIcon, height: MainPaneMetrics.sidebarIcon)
                    .accessibilityHidden(true)
                Text(title).onePlusText(.nav, color: muted ? OnePlusColor.muted : OnePlusColor.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MainPaneMetrics.sidebarRowInset)
            .frame(height: OnePlusMetrics.navRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(selected: selected, radius: OnePlusMetrics.panelRadius))
        .accessibilityAddTraits(selected ? .isSelected : []).help(title)
    }
}

/// A neutral rounded tile for sidebar rows that are not tools.
struct MainSymbolTile: View {
    let systemImage: String
    var size = MainPaneMetrics.sidebarIcon

    var body: some View {
        Image(systemName: systemImage).font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(OnePlusColor.ink)
            .frame(width: size, height: size)
            .background(OnePlusColor.selectedControl)
            .toolIconTile(size: size)
    }
}

struct MainAppIconTile: View {
    var size = MainPaneMetrics.sidebarIcon

    var body: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
            .resizable().scaledToFit().frame(width: size, height: size)
    }
}

import SwiftUI
import OnePlusUI

// shortcut: header geometry lives in the app until OnePlusUI has a Linear page header row; move it there at the next tag.
enum MainPaneMetrics {
    static let headerIcon: CGFloat = 32
    static let headerPadding: CGFloat = 10
    static let headerLineGap: CGFloat = 2
}

extension OnePlusWindowCanvas {
    // shortcut: `isApplet` is the only 1.1.0 way to center the traffic lights on C = 22 for the 44 pt v15 toolbar; use a v15 canvas flag when OnePlusUI adds one.
    static let mainWindow = Self(width: 820 + DemoMode.mainWindowExtraWidth, height: 660, sidebarWidth: OnePlusLinearMetrics.sidebarWidth, isApplet: true)
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

/// The v15 Linear shell: the 215 pt sidebar and one pane on the window surface, with no texture.
struct MainWindowShell<Sidebar: View, Content: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(maxHeight: .infinity).clipped()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }
        .background(OnePlusLinearColor.window)
        .ignoresSafeArea()
        .onePlusFixedCanvas(.mainWindow)
        .onePlusNeutralControls()
    }
}

/// A captioned group of v14 setting rows inside the Linear pane body.
struct MainSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionCaptionBelow) {
            if let title { OnePlusLinearSectionCaption(title) }
            OnePlusCard { content }
        }
    }
}

/// The compact identity row at the top of a tool or About page: icon, name, description, and page controls.
struct MainPageHeader<Icon: View, Controls: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let controls: Controls

    var body: some View {
        OnePlusLinearList {
            HStack(spacing: OnePlusLinearMetrics.toolRowGap) {
                icon.frame(width: MainPaneMetrics.headerIcon, height: MainPaneMetrics.headerIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: MainPaneMetrics.headerLineGap) {
                    Text(title).font(.system(size: OnePlusLinearMetrics.body, weight: .semibold))
                        .tracking(OnePlusLinearMetrics.bodyTracking)
                        .foregroundStyle(OnePlusLinearColor.ink).lineLimit(1).help(title)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.system(size: OnePlusLinearMetrics.control))
                        .foregroundStyle(OnePlusLinearColor.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true).help(subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                controls
            }
            .padding(.horizontal, OnePlusLinearMetrics.toolRowPadding)
            .padding(.vertical, MainPaneMetrics.headerPadding)
        }
    }
}

/// Row artwork for the package parts that take an `Image`: the tool's logo, its plugin icon file, or its glyph.
enum MainToolIcon {
    static func image(for tool: any Tool) -> Image {
        if let url = tool.iconFileURL { return Image(nsImage: NSImage(byReferencing: url)) }
        if !tool.logoAsset.isEmpty { return Image(tool.logoAsset) }
        return ToolGlyph(rawValue: tool.id)?.image ?? Image(systemName: tool.icon)
    }

    static var app: Image { Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage) }
}

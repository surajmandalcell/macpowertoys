import AppKit
import SwiftUI
import XCTest
import OnePlusUI
@testable import powertoys

@MainActor
final class LauncherGridTests: XCTestCase {
    private static let paneWidth = OnePlusWindowCanvas.mainWindow.size.width - OnePlusWindowCanvas.mainWindow.sidebarWidth

    func testMainWindowCentersItsTrafficLightsOnTheToolbar() {
        XCTAssertEqual(OnePlusWindowCanvas.mainWindow.size, CGSize(width: 820, height: 660))
        XCTAssertEqual(OnePlusWindowCanvas.mainWindow.centerline, OnePlusLinearMetrics.toolbar / 2)
    }

    func testOverviewNamesAndSummariesFitTheirColumns() {
        let fixed = OnePlusLinearMetrics.toolIcon + OnePlusLinearMetrics.toolNameWidth + OnePlusLinearMetrics.starSlot
            + OnePlusLinearMetrics.switchSize.width + Self.chevronWidth + 5 * OnePlusLinearMetrics.toolRowGap
        let summaryWidth = Self.paneWidth - 2 * OnePlusLinearMetrics.gutter - 2 * OnePlusLinearMetrics.toolRowPadding - fixed
        for tool in ToolRegistry.builtInTools {
            XCTAssertFalse(tool.summary.isEmpty, tool.id)
            XCTAssertLessThanOrEqual(Self.width(tool.summary, weight: .regular), summaryWidth, tool.id)
            XCTAssertLessThanOrEqual(Self.width(tool.name, weight: .medium), OnePlusLinearMetrics.toolNameWidth, tool.id)
        }
    }

    func testCatalogTabsCountEveryToolAndFilterTheRows() {
        let tools = ToolRegistry.builtInTools
        let favorites: Set<String> = ["ruler", "nettoys"]
        let disabled: Set<String> = ["awake", "logs", "disk-explorer"]
        let all = MainCatalog.preparedRows(tools, query: "", filter: .all, favorites: favorites, disabled: disabled)
        let tabs = MainCatalog.tabs(total: all.total, enabled: all.enabled, favorites: all.favorites)
        XCTAssertEqual(tools.count, 12)
        XCTAssertEqual(tabs.map(\.id), [.all, .enabled, .favorites])
        XCTAssertEqual(tabs.map(\.title), ["All", "Enabled", "Favorites"])
        XCTAssertEqual(tabs.map(\.count), [12, 9, 2])
        let enabled = MainCatalog.preparedRows(tools, query: "", filter: .enabled, favorites: favorites, disabled: disabled)
        XCTAssertEqual(enabled.visible.count, 9)
        XCTAssertTrue(enabled.visible.allSatisfy { !disabled.contains($0.id) })
        let starred = MainCatalog.preparedRows(tools, query: "", filter: .favorites, favorites: favorites, disabled: disabled)
        XCTAssertEqual(Set(starred.visible.map(\.id)), favorites)
        XCTAssertEqual(starred.groups.map(\.category), MainCatalog.groups(starred.visible).map(\.category))
    }

    func testFavoriteChangesAddAndRemoveOneTool() {
        let start: Set<String> = ["ruler"]
        XCTAssertEqual(MainCatalog.setting(favorite: true, for: "logs", in: start), ["ruler", "logs"])
        XCTAssertEqual(MainCatalog.setting(favorite: false, for: "ruler", in: start), [])
        XCTAssertEqual(MainCatalog.setting(favorite: true, for: "ruler", in: start), start)
    }

    func testToolRowOpensItsPageAndStarsItsTool() throws {
        let tool = try XCTUnwrap(ToolRegistry.tool(for: "color-picker"))
        var opened = 0
        var favorite = false
        let host = Self.host(MainToolRowSample(tool: tool, favorite: Binding(get: { favorite }, set: { favorite = $0 })) {
            opened += 1
        }, size: CGSize(width: Self.paneWidth - 2 * OnePlusLinearMetrics.gutter, height: OnePlusLinearMetrics.toolRow))
        XCTAssertEqual(try XCTUnwrap(Self.element(in: host, label: "Open Color Picker")).accessibilityPerformPress?(), true)
        XCTAssertEqual(opened, 1)
        let row = try XCTUnwrap(Self.element(in: host, label: "\(tool.name), \(tool.summary)"))
        let actions = ((row.accessibilityCustomActions?() ?? nil) ?? []) as [NSAccessibilityCustomAction]
        let star = try XCTUnwrap(actions.first { $0.name == "Add to Favorites" })
        if let handler = star.handler { XCTAssertTrue(handler()) } else {
            let target = try XCTUnwrap(star.target as? NSObject)
            _ = target.perform(try XCTUnwrap(star.selector), with: star)
        }
        XCTAssertTrue(favorite)
        host.window?.close()
    }

    func testCatalogTabsEndOnTheContentInsetAndNeverMove() throws {
        var frames: [[ClosedRange<CGFloat>]] = []
        for filter in [MainCatalogFilter.all, .favorites] {
            let bitmap = try Self.render(ToolbarSample(filter: filter),
                                         size: CGSize(width: Self.paneWidth, height: OnePlusLinearMetrics.toolbar), scheme: .dark)
            let scale = CGFloat(bitmap.pixelsWide) / Self.paneWidth
            let accent = Self.accentColumns(bitmap)
            XCTAssertFalse(accent.isEmpty, "\(filter)")
            if filter == .favorites {
                XCTAssertEqual(CGFloat(accent.upperBound + 1) / scale, Self.paneWidth - OnePlusLinearMetrics.gutter, accuracy: 1)
            }
            frames.append(Self.labelClusters(bitmap, from: Int(Self.paneWidth * scale / 2)).map {
                CGFloat($0.lowerBound) / scale...CGFloat($0.upperBound + 1) / scale
            })
        }
        XCTAssertEqual(frames[0].count, 3)
        XCTAssertEqual(frames[0].count, frames[1].count)
        for (before, after) in zip(frames[0], frames[1]) {
            XCTAssertEqual(before.lowerBound, after.lowerBound, accuracy: 1)
            XCTAssertEqual(before.upperBound, after.upperBound, accuracy: 1)
        }
        let last = try XCTUnwrap(frames[1].last)
        XCTAssertEqual(last.upperBound, Self.paneWidth - OnePlusLinearMetrics.gutter, accuracy: 1.5)
    }

    func testMainWindowRendersTheLinearStructureInBothAppearances() throws {
        let captures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/redesign/captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        for page in ["all-tools", "ruler", "settings"] {
            for scheme in [ColorScheme.dark, .light] {
                let bitmap = try Self.render(MainWindowSample(page: page), size: OnePlusWindowCanvas.mainWindow.size, scheme: scheme)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let name = "mainwin-\(page)-\(scheme == .dark ? "dark" : "light").png"
                try data.write(to: captures.appendingPathComponent(name))
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    // MARK: - Helpers

    private static let chevronWidth: CGFloat = {
        let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        return image?.size.width ?? 8
    }()

    private static func width(_ text: String, weight: NSFont.Weight) -> CGFloat {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: OnePlusLinearMetrics.body, weight: weight),
            .kern: OnePlusLinearMetrics.bodyTracking
        ]).size().width
    }

    private static func host<Content: View>(_ view: Content, size: CGSize, scheme: ColorScheme = .dark) -> NSHostingView<some View> {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        return host
    }

    private static func render<Content: View>(_ view: Content, size: CGSize, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let savedAppearance = NSApp.appearance
        defer { NSApp.appearance = savedAppearance }
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        NSApp.appearance = appearance
        let host = host(view, size: size, scheme: scheme)
        defer { host.window?.close() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        return bitmap
    }

    /// SwiftUI's accessibility nodes are private NSObject types, so the walk uses dynamic dispatch.
    private static func element(in root: Any, label: String) -> AnyObject? {
        let children: [Any] = ((root as AnyObject).accessibilityChildren?() ?? nil) ?? []
        for child in children {
            let object = child as AnyObject
            if (object.accessibilityLabel?() ?? nil) == label { return object }
            if let found = element(in: child, label: label) { return found }
        }
        return nil
    }

    /// Columns that hold the coral underline in the bottom rows of the toolbar.
    private static func accentColumns(_ bitmap: NSBitmapImageRep) -> ClosedRange<Int> {
        var columns: [Int] = []
        for x in 0..<bitmap.pixelsWide {
            for y in (bitmap.pixelsHigh - bitmap.pixelsHigh / 10)..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.8, color.greenComponent < 0.5, color.blueComponent < 0.45 { columns.append(x); break }
            }
        }
        return (columns.first ?? 0)...(columns.last ?? -1)
    }

    /// Horizontal runs of label pixels in the trailing half, above the underline; gaps wider than 10 pt split tabs.
    private static func labelClusters(_ bitmap: NSBitmapImageRep, from start: Int) -> [ClosedRange<Int>] {
        let scale = bitmap.pixelsWide / Int(paneWidth)
        guard let background = bitmap.colorAt(x: start, y: 2)?.usingColorSpace(.sRGB) else { return [] }
        func ink(_ x: Int) -> Bool {
            for y in (bitmap.pixelsHigh / 5)..<(bitmap.pixelsHigh * 4 / 5) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(color.redComponent - background.redComponent) + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent) > 0.45 { return true }
            }
            return false
        }
        var clusters: [ClosedRange<Int>] = []
        var current: ClosedRange<Int>?
        for x in start..<bitmap.pixelsWide where ink(x) {
            if let range = current, x - range.upperBound <= 10 * scale { current = range.lowerBound...x } else {
                if let range = current { clusters.append(range) }
                current = x...x
            }
        }
        if let current { clusters.append(current) }
        return clusters
    }
}

private struct MainToolRowSample: View {
    let tool: any Tool
    @Binding var favorite: Bool
    let open: () -> Void
    @FocusState private var focus: String?

    var body: some View {
        MainToolRow(tool: tool, favorite: $favorite, focus: $focus, move: { _ in }, typeSelect: { _ in }, open: open)
    }
}

private struct ToolbarSample: View {
    @State var filter: MainCatalogFilter

    var body: some View {
        OnePlusLinearPaneToolbar(title: "All tools", canGoBack: true, canGoForward: false, back: {}, forward: {}) {
            MainCatalogTabs(filter: $filter)
        }
        .background(OnePlusLinearColor.window)
    }
}

private struct MainWindowSample: View {
    let page: String
    @State private var filter = MainCatalogFilter.all
    @State private var settingsTab = MainSettingsTab.general

    var body: some View {
        MainWindowShell {
            ToolSidebarView(selectedTool: .constant(page), searchText: .constant(""))
        } content: {
            VStack(spacing: 0) {
                OnePlusLinearPaneToolbar(title: title, canGoBack: true, canGoForward: false, back: {}, forward: {}) {
                    switch page {
                    case "all-tools": MainCatalogTabs(filter: $filter)
                    case "settings": OnePlusLinearTextTabs(tabs: MainSettingsView.tabs, selection: $settingsTab)
                    default: EmptyView()
                    }
                }
                switch page {
                case "all-tools": AllToolsGridView(selectedTool: .constant(page))
                case "settings": MainSettingsView(tab: $settingsTab)
                default: ToolAboutView(toolId: page)
                }
            }
        }
    }

    private var title: String {
        switch page {
        case "all-tools": "All tools"
        case "settings": "Settings"
        default: ToolRegistry.tool(for: page)?.name ?? page
        }
    }
}

import AppKit
import SwiftUI
import XCTest
import OnePlusUI
@testable import powertoys

@MainActor
final class LauncherGridTests: XCTestCase {
    func testOverviewSummariesFitOneRowLine() {
        let canvas = OnePlusWindowCanvas.mainWindow
        let paneWidth = canvas.size.width - canvas.sidebarWidth - 2 * MainPaneMetrics.gutter
        let trailingControls: CGFloat = 24 + 29 + 10 + 3 * OnePlusCatalogMetrics.gap
        let width = paneWidth - 2 * OnePlusCatalogMetrics.cardInset - MainPaneMetrics.rowIcon
            - OnePlusCatalogMetrics.gap - trailingControls
        let font = NSFont.systemFont(ofSize: OnePlusTextRole.caption.size(for: .regular))
        for tool in ToolRegistry.builtInTools {
            XCTAssertFalse(tool.summary.isEmpty, tool.id)
            let size = NSAttributedString(string: tool.summary, attributes: [.font: font]).size()
            XCTAssertLessThanOrEqual(size.width, width, tool.id)
        }
    }

    func testMainWindowRendersSettingsStructureInBothAppearances() throws {
        let size = OnePlusWindowCanvas.mainWindow.size
        let captures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/redesign/captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let savedAppearance = NSApp.appearance
        defer { NSApp.appearance = savedAppearance }
        for page in ["all-tools", "ruler", "settings"] {
            for scheme in [ColorScheme.dark, .light] {
                let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
                NSApp.appearance = appearance
                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = appearance
                defer { window.close() }
                let host = NSHostingView(rootView: MainWindowSample(page: page)
                    .environment(\.colorScheme, scheme))
                host.frame = NSRect(origin: .zero, size: size)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                host.layoutSubtreeIfNeeded()
                let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: representation) }
                let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                let name = "mainwin-\(page)-\(scheme == .dark ? "dark" : "light").png"
                try data.write(to: captures.appendingPathComponent(name))
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

private struct MainWindowSample: View {
    let page: String

    var body: some View {
        MainWindowShell {
            ToolSidebarView(selectedTool: .constant(page), searchText: .constant(""))
        } content: {
            VStack(spacing: 0) {
                MainPaneToolbar(title: title, canGoBack: true, canGoForward: false, back: {}, forward: {})
                switch page {
                case "all-tools": AllToolsGridView(selectedTool: .constant(page))
                case "settings": MainSettingsView(tab: .constant(.general))
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

import AppKit
import SwiftUI
import XCTest
import OnePlusUI
@testable import powertoys

@MainActor
final class LauncherGridTests: XCTestCase {
    func testBuiltInSummariesFitTwoCardLines() {
        let width = (OnePlusWindowCanvas.main.size.width - OnePlusWindowCanvas.main.sidebarWidth
            - 2 * OnePlusMetrics.gutter - 3 * OnePlusCatalogMetrics.gap) / 4
            - 2 * OnePlusCatalogMetrics.cardInset
        let font = NSFont.systemFont(ofSize: 12)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        for tool in ToolRegistry.builtInTools {
            XCTAssertFalse(tool.summary.isEmpty, tool.id)
            XCTAssertLessThanOrEqual(tool.summary.count, 60, tool.id)
            let text = NSAttributedString(string: tool.summary, attributes: [.font: font])
            let bounds = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
            XCTAssertLessThanOrEqual(bounds.height, 2 * lineHeight, tool.id)
        }
    }

    func testCatalogCardsUseEqualContentHeightsWithinEachRow() throws {
        let contentWidth = OnePlusWindowCanvas.main.size.width
            - OnePlusWindowCanvas.main.sidebarWidth
            - 2 * OnePlusMetrics.gutter
        let cardWidth = (contentWidth - CGFloat(OnePlusCatalogMetrics.columns - 1)
            * OnePlusCatalogMetrics.gap) / CGFloat(OnePlusCatalogMetrics.columns)
        let heights = ToolRegistry.builtInTools.map { tool in
            NSHostingView(rootView: LauncherCardSample(tool: tool).frame(width: cardWidth)).fittingSize.height
        }
        let height = try XCTUnwrap(heights.first)
        XCTAssertLessThan(height, 151, "Cards must not retain the reviewed fixed-height empty band")
        for cardHeight in heights {
            XCTAssertEqual(cardHeight, height, accuracy: 0.5)
        }
        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OnePlusCatalogMetrics.gap),
                           count: OnePlusCatalogMetrics.columns),
            spacing: OnePlusCatalogMetrics.gap
        ) {
            ForEach(Array(ToolRegistry.builtInTools.prefix(OnePlusCatalogMetrics.columns)), id: \.id) { tool in
                LauncherCardSample(tool: tool)
            }
        }
        .frame(width: contentWidth)

        let host = NSHostingView(rootView: grid)
        XCTAssertEqual(host.fittingSize.height, height, accuracy: 0.5)
    }

    func testLauncherFourColumnRender() throws {
        let canvas = OnePlusWindowCanvas.main
        let size = NSSize(width: canvas.size.width - canvas.sidebarWidth, height: canvas.size.height)
        for scheme in [ColorScheme.dark, .light] {
            let host = NSHostingView(
                rootView: AllToolsGridView(selectedTool: .constant("all-tools"))
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
            )
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()

            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let image = NSImage(size: size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Main catalog - Four columns - \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct LauncherCardSample: View {
    let tool: any Tool
    @FocusState private var focusedCard: String?

    var body: some View {
        MainToolCard(tool: tool, favorite: .constant(false), focusedToolID: .constant(nil),
                     bodyFocus: $focusedCard, move: { _ in }, typeSelect: { _ in }, select: {})
    }
}

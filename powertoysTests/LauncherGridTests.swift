import AppKit
import SwiftUI
import XCTest
import OnePlusUI
@testable import powertoys

@MainActor
final class LauncherGridTests: XCTestCase {
    func testFourCatalogCardsFitTheMainCanvas() {
        let contentWidth = OnePlusWindowCanvas.main.size.width
            - OnePlusWindowCanvas.main.sidebarWidth
            - 2 * OnePlusMetrics.gutter
        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OnePlusCatalogMetrics.gap),
                           count: OnePlusCatalogMetrics.columns),
            spacing: OnePlusCatalogMetrics.gap
        ) {
            ForEach(0..<4, id: \.self) { _ in
                Color.gray.frame(height: OnePlusCatalogMetrics.cardHeight)
            }
        }
        .frame(width: contentWidth)

        let host = NSHostingView(rootView: grid)
        XCTAssertEqual(host.fittingSize.height, 151)
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

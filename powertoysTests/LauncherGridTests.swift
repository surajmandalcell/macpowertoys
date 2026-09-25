import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class LauncherGridTests: XCTestCase {
    func testFourCardsFitWithScrollerWidthReserved() {
        let contentWidth = UtilityLayout.launcherContentSize.width
            - UtilityLayout.compactSidebarWidth
            - 2 * UtilityLayout.launcherContentInset
            - 16
        let grid = LazyVGrid(
            columns: UtilityLayout.launcherGridColumns,
            spacing: UtilityLayout.launcherGridSpacing
        ) {
            ForEach(0..<4, id: \.self) { _ in
                Color.gray.frame(height: 40)
            }
        }
        .frame(width: contentWidth)

        let host = NSHostingView(rootView: grid)
        XCTAssertEqual(host.fittingSize.height, 40)
    }

    func testLauncherGridContractsOnNarrowDisplays() {
        XCTAssertEqual(UtilityLayout.launcherGridColumns(for: 980).count, 4)
        XCTAssertEqual(UtilityLayout.launcherGridColumns(for: 804).count, 3)
        XCTAssertEqual(UtilityLayout.launcherGridColumns(for: 600).count, 2)
    }

    func testLauncherFourColumnRender() throws {
        let size = NSSize(width: 980, height: 676)
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
            attachment.name = "Launcher — Four Columns — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

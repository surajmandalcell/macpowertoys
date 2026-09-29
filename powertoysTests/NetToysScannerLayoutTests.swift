import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class NetToysScannerLayoutTests: XCTestCase {
    func testDefaultScannerColumnsStayInsideFixedViewport() async throws {
        let suite = "NetToysScannerLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("192.0.2.0/24", forKey: "nettoys.scanner.target")
        let model = NetToysScannerViewModel(archive: NetToysScanArchive(), defaults: defaults)
        let canvas = OnePlusWindowCanvas.netToys
        let workspaceWidth = canvas.size.width - canvas.sidebarWidth

        for scheme in [ColorScheme.dark, .light] {
            let host = NSHostingView(rootView: NetToysScannerView(model: model)
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, scheme)
                .frame(width: workspaceWidth, height: canvas.size.height))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: workspaceWidth, height: canvas.size.height)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()

            let table = try XCTUnwrap(findTable(in: host))
            let viewport = try XCTUnwrap(table.enclosingScrollView).contentView.bounds.width
            XCTAssertEqual(viewport, 1192, accuracy: 1)
            let columns = table.tableColumns.indices.filter { !table.tableColumns[$0].isHidden }
            XCTAssertEqual(columns.map { table.tableColumns[$0].title.uppercased() }, [
                "IP ADDRESS", "STATUS", "RESPONSE", "HOSTNAME", "MAC ADDRESS", "MAC VENDOR", "OPEN PORTS"
            ])
            for index in columns {
                XCTAssertLessThanOrEqual(table.rect(ofColumn: index).maxX, viewport + 1,
                                         "\(table.tableColumns[index].title) extends outside the scanner")
            }
        }
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let table = findTable(in: child) { return table }
        }
        return nil
    }
}

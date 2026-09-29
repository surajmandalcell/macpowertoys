import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class NetToysScannerLayoutTests: XCTestCase {
    func testScannerCachesFilteredAndSortedRows() throws {
        let suite = "NetToysScannerLayoutTests.cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let down = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.1")), isReachable: false,
            responseMilliseconds: nil, hostname: "router", macAddress: nil, vendor: nil, openPorts: []
        )
        let printer = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.2")), isReachable: true,
            responseMilliseconds: 2, hostname: "printer", macAddress: nil, vendor: nil, openPorts: [80]
        )
        let server = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.3")), isReachable: true,
            responseMilliseconds: 1, hostname: "server", macAddress: nil, vendor: nil, openPorts: [22]
        )
        let run = NetToysScanRun(target: "192.0.2.0/24", ports: [22, 80], duration: 1,
                                 results: [server, down, printer])
        let model = NetToysScannerViewModel(archive: NetToysScanArchive(runs: [run]), defaults: defaults)

        XCTAssertEqual(model.visibleResults.map(\.id), [down.id, printer.id, server.id])
        XCTAssertEqual(model.aliveResultCount, 2)
        XCTAssertEqual(model.openPortResultCount, 2)
        model.filter = .alive
        model.searchText = "server"
        XCTAssertEqual(model.visibleResults.map(\.id), [server.id])
        model.searchText = ""
        model.sortOrder = [KeyPathComparator(\NetToysScanResult.sortAddress, order: .reverse)]
        XCTAssertEqual(model.visibleResults.map(\.id), [server.id, printer.id])
        model.applyScanUpdate(NetToysScanResult(
            address: server.address, isReachable: false, responseMilliseconds: nil,
            hostname: server.hostname, macAddress: nil, vendor: nil, openPorts: []
        ))
        XCTAssertEqual(model.visibleResults.map(\.id), [printer.id])
        XCTAssertEqual(model.aliveResultCount, 1)
        XCTAssertEqual(model.openPortResultCount, 1)
        model.applyScanUpdate(NetToysScanResult(
            address: printer.address, isReachable: false, responseMilliseconds: nil,
            hostname: printer.hostname, macAddress: nil, vendor: nil, openPorts: []
        ))
        XCTAssertTrue(model.hasNoResponsiveHosts)
    }

    func testScannerDefaultTargetFollowsActiveSubnetUntilUserEdits() throws {
        let suite = "NetToysScannerLayoutTests.network.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("192.168.0.1/24", forKey: "nettoys.scanner.target")
        let model = NetToysScannerViewModel(archive: NetToysScanArchive(), defaults: defaults)
        let home = try XCTUnwrap(LocalIPv4Network(
            interfaceName: "en0", address: "192.168.1.23", netmask: "255.255.255.0"
        ))

        model.updateActiveNetwork(home)

        XCTAssertEqual(model.targetInput, "192.168.1.0/24")
        model.targetInput = "10.0.0.8"
        let office = try XCTUnwrap(LocalIPv4Network(
            interfaceName: "en0", address: "172.16.4.9", netmask: "255.255.255.0"
        ))
        model.updateActiveNetwork(office)
        XCTAssertEqual(model.targetInput, "10.0.0.8")

        let restored = NetToysScannerViewModel(archive: NetToysScanArchive(), defaults: defaults)
        restored.updateActiveNetwork(office)
        XCTAssertEqual(restored.targetInput, "10.0.0.8")
    }

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
            XCTAssertEqual(viewport, 1190, accuracy: 1)
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

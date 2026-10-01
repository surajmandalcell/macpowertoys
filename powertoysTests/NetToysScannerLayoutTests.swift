import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class NetToysScannerLayoutTests: XCTestCase {
    func testNumericSortsKeepTheirValuesAndDirectionWhenRestored() throws {
        let suite = "NetToysScannerLayoutTests.numeric.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let low = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.1")), isReachable: true,
            responseMilliseconds: 20, hostname: nil, macAddress: nil, vendor: nil,
            openPorts: [], ttl: 64, packetLossPercent: 2
        )
        let high = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.2")), isReachable: true,
            responseMilliseconds: 100, hostname: nil, macAddress: nil, vendor: nil,
            openPorts: [], ttl: 128, packetLossPercent: 10
        )
        let unknown = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.3")), isReachable: false,
            responseMilliseconds: nil, hostname: nil, macAddress: nil, vendor: nil, openPorts: []
        )
        let archive = NetToysScanArchive(runs: [NetToysScanRun(
            target: "192.0.2.0/24", ports: [], duration: 1, results: [high, low, unknown]
        )])
        let model = NetToysScannerViewModel(archive: archive, defaults: defaults)
        let comparators = [
            KeyPathComparator(\NetToysScanResult.responseMilliseconds),
            KeyPathComparator(\NetToysScanResult.ttl),
            KeyPathComparator(\NetToysScanResult.packetLossPercent),
        ]
        for comparator in comparators {
            for order in [SortOrder.forward, .reverse] {
                var comparator = comparator
                comparator.order = order
                model.sortOrder = [comparator]
                let expected = order == .forward ? [unknown.id, low.id, high.id] : [high.id, low.id, unknown.id]
                XCTAssertEqual(model.visibleResults.map(\.id), expected)
                let restored = NetToysScannerViewModel(archive: archive, defaults: defaults)
                XCTAssertEqual(restored.sortOrder.first?.keyPath, comparator.keyPath)
                XCTAssertEqual(restored.visibleResults.map(\.id), expected)
            }
        }
    }

    func testDuplicateImportsAreRejectedAndDuplicateArchiveRowsDoNotCrash() throws {
        let suite = "NetToysScannerLayoutTests.duplicates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let row = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.1")), isReachable: true,
            responseMilliseconds: 1, hostname: nil, macAddress: nil, vendor: nil, openPorts: [22], comment: "From file"
        )
        XCTAssertThrowsError(try NetToysScanImport.savedResults(NetToysScanExport.savedResults([row, row]))) {
            guard case NetToysScanImport.ImportError.duplicateAddress = $0 else {
                return XCTFail("Expected the duplicate-address error, got \($0)")
            }
        }
        let model = NetToysScannerViewModel(archive: NetToysScanArchive(runs: [NetToysScanRun(
            target: row.id, ports: [22], duration: 1, results: [row, row]
        )]), defaults: defaults)
        XCTAssertEqual(model.results, [row])
        XCTAssertEqual(model.annotation(for: row.id).comment, "From file")
        var rescanned = row
        rescanned.comment = nil
        model.applyScanUpdate(rescanned)
        XCTAssertEqual(model.results.first?.comment, "From file")
        model.selection = [row.id]
        model.clearRestoredResults()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.visibleResults.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.completed, 0)
        XCTAssertEqual(model.total, 0)
        XCTAssertNil(model.lastDuration)
        XCTAssertNil(model.lastScanTarget)
    }

    func testScannerCachesFilteredAndSortedRows() throws {
        let suite = "NetToysScannerLayoutTests.cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let down = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.1")), isReachable: false,
            responseMilliseconds: nil, hostname: "router", macAddress: nil, vendor: nil, openPorts: []
        )
        var printer = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.2")), isReachable: true,
            responseMilliseconds: 2, hostname: "printer", macAddress: nil, vendor: nil, openPorts: []
        )
        let server = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.3")), isReachable: true,
            responseMilliseconds: 1, hostname: "server", macAddress: nil, vendor: nil, openPorts: [22]
        )
        let model = NetToysScannerViewModel(archive: NetToysScanArchive(), defaults: defaults)

        model.applyScanUpdate(down)
        XCTAssertEqual(model.visibleResults.map(\.id), [down.id])
        XCTAssertEqual(model.aliveResultCount, 0)
        model.applyScanUpdate(printer)
        XCTAssertEqual(model.visibleResults.map(\.id), [down.id, printer.id])
        XCTAssertEqual(model.aliveResultCount, 1)
        XCTAssertEqual(model.openPortResultCount, 0)
        printer.openPorts = [80]
        model.applyScanUpdate(printer)
        model.applyScanUpdate(server)
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

        XCTAssertEqual(model.targetInputForScan(activeNetwork: home), "192.168.1.0/24")

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
        model.applyScanUpdate(NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.0.2.1")), isReachable: false,
            responseMilliseconds: nil, hostname: nil, macAddress: nil, vendor: nil, openPorts: []
        ))
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
            XCTAssertEqual(table.numberOfRows, 1, "All must retain unreachable hosts for selection and rescan")
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

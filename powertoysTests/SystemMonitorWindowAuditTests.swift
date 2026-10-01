import Foundation
import XCTest
@testable import powertoys

final class SystemMonitorWindowAuditTests: XCTestCase {
    @MainActor
    func testWindowSamplesImmediatelyAndKeepsItsLatestSnapshotOnReopen() async throws {
        let service = SystemMonitorService(menuSettings: SystemMonitorMenuSettings(), observesWake: false)
        service.startDetailed(owner: "startup-test")
        defer { service.stopDetailed(owner: "startup-test") }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while service.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let first = try XCTUnwrap(service.snapshot)
        service.stopDetailed(owner: "startup-test")
        service.startDetailed(owner: "startup-test")
        XCTAssertEqual(service.snapshot?.timestamp, first.timestamp)
        XCTAssertEqual(service.timerOwnerCount, 1)
        service.stopDetailed(owner: "startup-test")
        XCTAssertEqual(service.timerOwnerCount, 0)
    }

    func testBatteryDetailsReserveFourRowsUntilCompletedAndRetainValidRefresh() {
        let pending = SystemMonitorWindowView.batteryDetailRows(for: nil)
        XCTAssertEqual(pending.map { $0.0 }, ["Health", "Cycle count", "Voltage", "Amperage"])
        XCTAssertEqual(pending.map { $0.1 }, Array(repeating: "—", count: 4))
        let details = SystemMonitorBatteryDetails(cycleCount: 12, health: "Normal", currentCapacity: nil,
                                                  maximumCapacity: nil, voltageMillivolts: 12000, amperageMilliamps: -500)
        let rows = SystemMonitorWindowView.batteryDetailRows(for: details)
        XCTAssertEqual(rows.count, pending.count)
        XCTAssertEqual(rows[0].1, "Normal")
        XCTAssertEqual(rows[1].1, "12")
        let old = SystemMonitorSample(timestamp: Date(), cpuUsage: nil, memoryUsed: nil, memoryTotal: nil,
                                      gpuUsage: nil, networkDownload: nil, networkUpload: nil, diskUsed: nil,
                                      diskTotal: nil, batteryPercent: 60, batteryCharging: false, thermalState: nil,
                                      loadAverage: nil, unavailableMetrics: [], batteryDetails: details)
        let pendingSample = SystemMonitorSample(timestamp: Date(), cpuUsage: nil, memoryUsed: nil, memoryTotal: nil,
                                                gpuUsage: nil, networkDownload: nil, networkUpload: nil, diskUsed: nil,
                                                diskTotal: nil, batteryPercent: nil, batteryCharging: nil, thermalState: nil,
                                                loadAverage: nil, unavailableMetrics: [])
        XCTAssertEqual(pendingSample.preservingAvailableValues(from: old).batteryDetails?.cycleCount, 12)
    }

    func testPendingBatteryDoesNotClaimTheHardwareIsAbsent() {
        func sample(percent: Int? = nil, charging: Bool? = nil,
                    unavailable: Set<SystemMonitorMenuMetric> = []) -> SystemMonitorSample {
            SystemMonitorSample(timestamp: Date(), cpuUsage: nil, memoryUsed: nil, memoryTotal: nil,
                                gpuUsage: nil, networkDownload: nil, networkUpload: nil,
                                diskUsed: nil, diskTotal: nil, batteryPercent: percent,
                                batteryCharging: charging, thermalState: nil, loadAverage: nil,
                                unavailableMetrics: unavailable)
        }
        XCTAssertEqual(SystemMonitorWindowView.batteryDetail(for: nil), "—")
        XCTAssertEqual(SystemMonitorWindowView.batteryDetail(for: sample()), "—")
        XCTAssertEqual(SystemMonitorWindowView.batteryDetail(for: sample(unavailable: [.battery])),
                       "No internal battery detected")
        XCTAssertEqual(SystemMonitorWindowView.batteryDetail(for: sample(percent: 65)), "—")
        XCTAssertEqual(SystemMonitorWindowView.batteryDetail(for: sample(percent: 65, charging: true)),
                       "Connected to power")
        XCTAssertEqual(SystemMonitorWindowView.batteryDetail(for: sample(percent: 65, charging: false)),
                       "On battery")
    }

    func testWindowHistoryKeepsOneAndTwoMinuteSeriesBoundedAndMissingValuesAbsent() {
        var history = SystemMonitorHistory()
        for index in 0..<130 {
            let sample = SystemMonitorSample(
                timestamp: Date(timeIntervalSince1970: Double(index)), cpuUsage: Double(index),
                memoryUsed: nil, memoryTotal: nil, gpuUsage: nil,
                networkDownload: Double(index), networkUpload: Double(index * 2),
                diskUsed: nil, diskTotal: nil, batteryPercent: nil, batteryCharging: nil,
                thermalState: nil, loadAverage: nil, unavailableMetrics: []
            )
            history.append(sample, metrics: [.cpu, .network, .memory])
        }
        XCTAssertEqual(history.windowValues(for: .cpu, minutes: 1).values, (70..<130).map(Double.init))
        XCTAssertEqual(history.windowValues(for: .cpu, minutes: 2).values, (10..<130).map(Double.init))
        XCTAssertEqual(history.windowValues(for: .cpu, minutes: 5).values.count, 120)
        XCTAssertEqual(history.windowValues(for: .memory, minutes: 2).values, [])
        XCTAssertEqual(history.windowValues(for: .network, minutes: 2).range.upperBound, 258 * 1.15)
    }

    func testChartLabelsArePreparedWithoutRenderingAndHandleMissingValues() {
        XCTAssertEqual(TaskManagerHistoryChart.formattedLabels(values: [], unit: "%").accessibility, "No history")
        let labels = TaskManagerHistoryChart.formattedLabels(values: [1.25, 50, .infinity], unit: "%")
        XCTAssertEqual(labels.hover[1], 50.0.formatted(.number.precision(.fractionLength(0))) + " %")
        XCTAssertEqual(labels.hover[2], "Unavailable")
        XCTAssertEqual(labels.accessibility, "Latest value unavailable")
        XCTAssertEqual(TaskManagerHistoryChart.formattedLabels(values: [50], unit: "").accessibility,
                       "Latest value " + 50.0.formatted())
    }

    @MainActor
    func testProtectedProcessTableMenusOmitTermination() {
        for (pid, started, expected) in [(Int32(1), UInt64(1), ["Inspect", "Copy executable path"]),
                                         (Int32.max, 0, ["Inspect"]),
                                         (Int32.max, 1, ["Inspect", "Copy executable path", "Quit", "Force Quit"])] {
            let process = SystemMonitorProcess(pid: pid, started: started, name: "Test", cpuPercent: nil,
                                                residentBytes: 0, virtualBytes: 0, threads: 0, parentPID: 1,
                                                userID: UInt32.max, executablePath: started == 0 ? "Protected process" : "/bin/test")
            let menu = SystemMonitorProcessActions.tableActions(process, inspect: {}, copyPath: { _ in }, confirm: { _, _ in })
            XCTAssertEqual(menu.map(\.title), expected)
        }
    }

    func testProcessActionsRejectStartupSelfUnknownIdentityAndUnavailablePaths() {
        for (pid, started, allowed) in [(Int32(1), UInt64(1), false),
                                       (ProcessInfo.processInfo.processIdentifier, 1, false),
                                       (Int32.max, 0, false), (Int32.max, 1, true)] {
            let process = SystemMonitorProcess(
                pid: pid, started: started, name: "Test", cpuPercent: nil,
                residentBytes: 0, virtualBytes: 0, threads: 0, parentPID: 1,
                userID: UInt32.max, executablePath: started == 0 ? "Protected process" : "/bin/test"
            )
            XCTAssertEqual(SystemMonitorProcessActions.canTerminate(process), allowed)
            XCTAssertEqual(SystemMonitorProcessActions.canCopyPath(process), started != 0)
        }
    }

    func testMemoryAllocationKeepsMissingDataUnknownAndSegmentsWithinRAM() throws {
        let details = SystemMonitorMemoryDetails(wired: 30, compressed: 20, cached: 10,
                                                swapUsed: nil, pageIns: 0, pageOuts: 0)
        XCTAssertNil(SystemMonitorMemoryAllocation(used: nil, total: 100, details: details))
        XCTAssertNil(SystemMonitorMemoryAllocation(used: 80, total: 100, details: nil))
        XCTAssertNil(SystemMonitorMemoryAllocation(used: 80, total: 0, details: details))
        let allocation = try XCTUnwrap(SystemMonitorMemoryAllocation(used: 80, total: 100, details: details))
        XCTAssertEqual([allocation.applications, allocation.wired, allocation.compressed, allocation.available],
                       [30, 30, 20, 20])
        let clamped = try XCTUnwrap(SystemMonitorMemoryAllocation(used: 15, total: 100, details: details))
        XCTAssertEqual([clamped.applications, clamped.wired, clamped.compressed, clamped.available], [0, 15, 0, 85])
    }

    func testReportExportsReadableTextAndRawJSONAndReportsWriteFailure() throws {
        let category = TaskManagerReportCategory(
            id: "hardware", title: "Hardware", symbol: "cpu", group: "Hardware",
            sections: [TaskManagerReportSection(
                title: "Overview", rows: [TaskManagerReportRow(
                    field: "CPU cores", value: "12 cores", rawField: "number_processors", rawValue: "proc 12"
                )], rawTitle: "hardware_overview"
            )]
        )
        let text = try TaskManagerReportExport.data(categories: [category], format: .text)
        XCTAssertEqual(String(decoding: text, as: UTF8.self), "Hardware\n\nOverview\nCPU cores: 12 cores")
        let json = try TaskManagerReportExport.data(categories: [category], format: .json)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        let sections = try XCTUnwrap(report[0]["sections"] as? [[String: Any]])
        let rows = try XCTUnwrap(sections[0]["rows"] as? [[String: String]])
        XCTAssertEqual(sections[0]["rawTitle"] as? String, "hardware_overview")
        XCTAssertEqual(rows[0]["rawField"], "number_processors")
        XCTAssertEqual(rows[0]["rawValue"], "proc 12")
        XCTAssertEqual(rows[0]["value"], "12 cores")
        XCTAssertThrowsError(try TaskManagerReportExport.write(
            categories: [category], format: .text,
            to: URL(fileURLWithPath: "/dev/null/report.txt")
        ))
    }
}

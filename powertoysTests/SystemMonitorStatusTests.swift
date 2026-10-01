import AppKit
import XCTest
@testable import powertoys

@MainActor
final class SystemMonitorStatusTests: XCTestCase {
    func testRetainedReadingsKeepTheirSuccessfulTimeAndRecover() {
        let old = sample(at: 1_000, cpu: 42)
        let baseline = sample(at: 1_100, cpu: nil).preservingAvailableValues(from: old)
        let failed = sample(at: 1_200, cpu: nil, unavailable: [.cpu]).preservingAvailableValues(from: baseline)
        XCTAssertEqual(failed.cpuUsage, 42)
        XCTAssertEqual(failed.lastSuccessfulReads[.cpu], old.timestamp)
        XCTAssertEqual(failed.lastSuccessfulReads[.memory], failed.timestamp)
        let recovered = sample(at: 1_300, cpu: 43).preservingAvailableValues(from: failed)
        XCTAssertEqual(recovered.lastSuccessfulReads[.cpu], recovered.timestamp)
        XCTAssertEqual(SystemMonitorFreshness.allowance(interval: 1), 3)
        XCTAssertEqual(SystemMonitorFreshness.allowance(interval: 60), 180)
        let pages = TaskManagerMenuProjection.prepare(sample: failed, history: .init(), staleMetrics: [.cpu])
        XCTAssertEqual(pages[.cpu]?.value, "42%")
        XCTAssertEqual(pages[.cpu]?.rows.last?.value, "Stale")
        XCTAssertFalse(pages[.memory]?.rows.contains { $0.value == "Stale" } ?? true)
    }

    func testStatusFontAndConfiguredEnvelopeStayBounded() {
        XCTAssertEqual(SystemMonitorStatusText.width(of: "11%"), SystemMonitorStatusText.width(of: "88%"), accuracy: 0.01)
        let items = SystemMonitorMenuMetric.allCases.map {
            SystemMonitorMenuItemConfiguration(metric: $0, enabled: true, memoryUnit: .used,
                diskUnit: .used, batteryDisplay: .both, thermalDisplay: .full)
        }
        let widths = Dictionary(uniqueKeysWithValues: items.map { ($0.metric, SystemMonitorStatusText.width(for: $0)) })
        XCTAssertLessThan(SystemMonitorStatusText.length(for: items, widths: widths), 1_280)
        let bits = SystemMonitorMenuItemConfiguration(metric: .network, networkUnit: .bits)
        XCTAssertGreaterThanOrEqual(SystemMonitorStatusText.width(for: bits),
                                    SystemMonitorStatusText.width(of: "↓102 Mb/s ↑102 Mb/s"))
        for item in items {
            for text in SystemMonitorMenuRenderer.widthCandidates(for: item) {
                XCTAssertLessThanOrEqual(SystemMonitorStatusText.width(of: text), widths[item.metric]!, text)
            }
        }
    }

    func testNativeItemLengthAndStaleAccessibilityKeepValues() throws {
        let suite = "SystemMonitorStatusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SystemMonitorMenuController(defaults: defaults)
        var settings = SystemMonitorMenuSettings(enabled: true, items: [.init(metric: .cpu, enabled: true)])
        controller.configure(settings: settings)
        controller.update(sample: sample(at: 1_000, cpu: 9), dueMetrics: [.cpu])
        let length = controller.statusItemLength(for: "group")
        controller.update(sample: sample(at: 1_001, cpu: 100), dueMetrics: [.cpu])
        XCTAssertEqual(controller.statusItemLength(for: "group"), length)
        controller.update(sample: nil, dueMetrics: [], staleMetrics: [.cpu])
        XCTAssertEqual(controller.displayedValue(for: .cpu), "100%")
        XCTAssertTrue(controller.statusItemHelp(for: "group")?.contains("Stale") == true)
        settings.enabled = false
        controller.configure(settings: settings)
    }

    func testAttachmentTintFollowsNativeAppearanceWithoutChangingGeometry() throws {
        let image = try XCTUnwrap(StatusItemIcon.attachmentSymbol("cpu"))
        XCTAssertFalse(image.isTemplate)
        var brightness: [CGFloat] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = image.size
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                image.draw(in: NSRect(origin: .zero, size: image.size))
                NSGraphicsContext.restoreGraphicsState()
            }
            let colors = (0..<28).flatMap { y in (0..<28).compactMap { x in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            }}.filter { $0.alphaComponent > 0.5 }
            XCTAssertFalse(colors.isEmpty)
            brightness.append(colors.map(\.redComponent).reduce(0, +) / CGFloat(colors.count))
        }
        XCTAssertGreaterThan(brightness[1] - brightness[0], 0.5)
    }

    private func sample(at seconds: TimeInterval, cpu: Double?, unavailable: Set<SystemMonitorMenuMetric> = []) -> SystemMonitorSample {
        .init(timestamp: Date(timeIntervalSince1970: seconds), cpuUsage: cpu,
              memoryUsed: 6_000_000_000, memoryTotal: 10_000_000_000, gpuUsage: nil,
              networkDownload: nil, networkUpload: nil, diskUsed: nil, diskTotal: nil,
              batteryPercent: nil, batteryCharging: nil, thermalState: nil,
              loadAverage: nil, unavailableMetrics: unavailable)
    }
}

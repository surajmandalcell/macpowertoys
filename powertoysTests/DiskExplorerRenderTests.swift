import AppKit
import SwiftUI
import XCTest
@testable import powertoys

final class DiskExplorerRenderTests: XCTestCase {
    @MainActor func testResultTabsInBothAppearances() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<9 {
            let folder = root.appendingPathComponent("Folder \(index + 1)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: UInt8(index), count: (10 - index) * 4096)
                .write(to: folder.appendingPathComponent("Document \(index + 1).bin"))
        }
        let result = try DiskExplorerScanner.scan(root)
        let savedStyle = UserDefaults.standard.string(forKey: "diskExplorer.chartStyle")
        defer { UserDefaults.standard.set(savedStyle, forKey: "diskExplorer.chartStyle") }
        let size = NSSize(width: 1_120, height: 760)
        for (tab, style, scheme) in [
            (DiskResultTab.visualization, DiskChartStyle.treemap, ColorScheme.dark),
            (.visualization, .treemap, .light),
            (.visualization, .sunburst, .dark),
            (.visualization, .sunburst, .light),
            (.largestFiles, .treemap, .dark)
        ] {
            UserDefaults.standard.set(style.rawValue, forKey: "diskExplorer.chartStyle")
            let host = NSHostingView(rootView:
                DiskExplorerWindowView(model: DiskExplorerModel(preview: result),
                                       scansOnAppear: false, initialTab: tab)
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
            attachment.name = "Disk Explorer — \(tab.rawValue) — \(style.rawValue) — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

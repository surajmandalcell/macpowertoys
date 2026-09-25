import AppKit
import SwiftUI
import XCTest
@testable import powertoys

final class DiskExplorerRenderTests: XCTestCase {
    @MainActor func testModifyLayoutInBothAppearances() throws {
        let card = ManagedDisk(
            id: "disk10", name: "SDXC Reader", size: 15_634_268_160,
            bus: "Secure Digital", scheme: "GUID_partition_scheme", devicePath: "reader",
            writable: true, manageable: true, mediaRegistryID: 1, partitions: [
                ManagedPartition(id: "disk10s1", name: "EFI", content: "EFI",
                                 size: 209_715_200, mountPoint: nil, uuid: nil),
                ManagedPartition(id: "disk10s2", name: "DISKMAN", content: "Microsoft Basic Data",
                                 size: 15_424_552_960, mountPoint: "/Volumes/DISKMAN", uuid: "volume",
                                 fileSystem: "ExFAT")
            ]
        )
        let size = NSSize(width: 880, height: 700)
        for scheme in [ColorScheme.dark, .light] {
            let host = NSHostingView(rootView:
                DiskModifyView(previewDisks: [card])
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
            attachment.name = "Diskman Modify — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

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
            attachment.name = "Diskman — \(tab.rawValue) — \(style.rawValue) — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

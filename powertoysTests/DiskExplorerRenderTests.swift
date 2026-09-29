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
                ManagedPartition(id: "disk10s2", name: "WORK", content: "Apple_HFS",
                                 size: 6_000_000_000, mountPoint: "/Volumes/WORK", uuid: "work",
                                 fileSystem: "Mac OS Extended (Journaled)"),
                ManagedPartition(id: "disk10s3", name: "APFS", content: "Apple_APFS",
                                 size: 9_422_455_808, mountPoint: nil, uuid: nil,
                                 apfsContainer: "disk13"),
                ManagedPartition(id: "disk13s1", name: "ARCHIVE", content: "APFS Volume",
                                 size: 4_000_000_000, mountPoint: "/Volumes/ARCHIVE", uuid: "archive",
                                 apfsContainer: "disk13", isAPFSVolume: true)
            ]
        )
        let size = NSSize(width: 1224, height: 900)
        for scheme in [ColorScheme.dark, .light] {
            let host = NSHostingView(rootView:
                DiskModifyView(previewDisks: [card], previewPartitionID: "disk10s2")
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
        let result = largeHomeFixture()
        let warningResult = DiskScanResult(root: result.root, largestFiles: result.largestFiles,
                                           unreadableCount: 701,
                                           skippedVolumeCount: result.skippedVolumeCount,
                                           scannedAt: result.scannedAt, isComplete: true)
        let savedStyle = UserDefaults.standard.string(forKey: "diskExplorer.chartStyle")
        defer { UserDefaults.standard.set(savedStyle, forKey: "diskExplorer.chartStyle") }
        let size = NSSize(width: 1440, height: 900)
        for (tab, style, scheme) in [
            (DiskResultTab.visualization, DiskChartStyle.treemap, ColorScheme.dark),
            (.visualization, .treemap, .light),
            (.visualization, .sunburst, .dark),
            (.visualization, .sunburst, .light),
            (.largestFiles, .treemap, .dark),
            (.largestFiles, .treemap, .light),
            (.results, .treemap, .dark),
            (.results, .treemap, .light)
        ] {
            UserDefaults.standard.set(style.rawValue, forKey: "diskExplorer.chartStyle")
            let host = NSHostingView(rootView:
                DiskExplorerWindowView(model: DiskExplorerModel(preview: tab == .visualization ? warningResult : result),
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

    private func largeHomeFixture() -> DiskScanResult {
        func folder(_ path: String, children: [DiskEntry]) -> DiskEntry {
            let entry = DiskEntry(url: URL(fileURLWithPath: path), kind: .directory,
                                  allocatedBytes: children.reduce(0) { $0 + $1.allocatedBytes },
                                  apparentBytes: children.reduce(0) { $0 + $1.apparentBytes },
                                  fileCount: children.reduce(0) { $0 + $1.fileCount },
                                  directoryCount: 1 + children.reduce(0) { $0 + $1.directoryCount },
                                  modifiedAt: .distantPast, device: 1, inode: 1)
            entry.replaceChildren(children)
            return entry
        }
        let names = ["Library", "Projects", "Downloads", "Pictures", "Documents", "Desktop", "Music", "Movies", ".cache"]
            + (0..<124).map { "Small folder \($0)" }
        let folders = names.enumerated().map { index, name in
            let path = "/Users/Diskman/\(name)"
            let bytes = index < 9 ? Int64(10 - index) * 1_000_000_000 : 4096
            let file = DiskEntry(url: URL(fileURLWithPath: path + "/Document.bin"), kind: .file,
                                 allocatedBytes: bytes, apparentBytes: bytes, fileCount: 1, directoryCount: 0,
                                 modifiedAt: .distantPast, device: 1, inode: UInt64(index + 2))
            let aggregate = DiskEntry(url: URL(fileURLWithPath: path + "/folded"), kind: .aggregate,
                                      allocatedBytes: bytes / 2, apparentBytes: bytes / 2,
                                      fileCount: 12_000, directoryCount: 0, modifiedAt: .distantPast, device: 1, inode: 0)
            return folder(path, children: [file, folder(path + "/Contents", children: [aggregate])])
        }
        let root = folder("/Users/Diskman", children: folders)
        return DiskScanResult(root: root, largestFiles: Array(folders.compactMap { $0.children.first }.prefix(100)), unreadableCount: 0,
                              skippedVolumeCount: 0, scannedAt: Date(timeIntervalSince1970: 1_790_668_800), isComplete: true)
    }
}

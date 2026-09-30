import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

final class DiskExplorerRenderTests: XCTestCase {
    @MainActor func testLiveRingMembershipChangesKeepTheRootBandFilled() throws {
        func root(_ sizes: [Int64]) -> DiskEntry {
            let children = sizes.enumerated().map { index, bytes in
                DiskEntry(url: URL(fileURLWithPath: "/Diskman/folder-\(index)"), kind: .directory,
                          allocatedBytes: bytes, apparentBytes: bytes, fileCount: 1, directoryCount: 1,
                          modifiedAt: .distantPast, device: 1, inode: UInt64(index + 2))
            }
            return DiskEntry(url: URL(fileURLWithPath: "/Diskman"), kind: .directory,
                             allocatedBytes: sizes.reduce(0, +), apparentBytes: sizes.reduce(0, +),
                             fileCount: sizes.count, directoryCount: sizes.count + 1,
                             modifiedAt: .distantPast, device: 1, inode: 1, children: children)
        }
        let size = CGFloat(400)
        let radius = size / 2 - 10
        let sampleRadius = radius * (0.30 + 0.68 / 6) - 1
        let before = root([600, 500, 400, 300, 200, 100])
        let after = root([600, 500, 400, 300, 200, 2_000])
        for scheme in [ColorScheme.dark, .light] {
            let cache = DiskChartLayoutCache()
            func view(_ root: DiskEntry, revision: Date) -> some View {
                let key = DiskChartCacheKey(revision: revision, tab: .sunburst,
                    directoryID: root.id, measure: .space, apparent: false, scanComplete: false,
                    width: Int(size), height: Int(size))
                cache.store(DiskSunburstView.segments(for: root, apparent: false, measure: .space,
                                                     radius: radius, scanComplete: false), for: key)
                return DiskSunburstView(directory: root, apparent: false, measure: .space,
                    scanComplete: false, revision: revision, cache: cache, select: { _ in })
                    .frame(width: size, height: size).background(Color(nsColor: .magenta))
                    .environment(\.colorScheme, scheme)
                    .animation(.linear(duration: 1), value: revision)
            }
            let host = NSHostingView(rootView: view(before, revision: .distantPast))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: size, height: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            host.rootView = view(after, revision: .distantPast.addingTimeInterval(1))
            for _ in 0..<5 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                for degrees in stride(from: 1, to: 360, by: 2) {
                    let angle = Double(degrees) * .pi / 180
                    let x = (size / 2 + cos(angle) * sampleRadius) * CGFloat(bitmap.pixelsWide) / size
                    let y = (size / 2 + sin(angle) * sampleRadius) * CGFloat(bitmap.pixelsHigh) / size
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.deviceRGB))
                    XCTAssertGreaterThan(color.greenComponent, 0.05,
                                         "Missing root sector at \(degrees) degrees in \(scheme)")
                }
            }
        }
    }

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
        XCTAssertEqual(result.root.allocatedBytes, 81_000_761_856)
        XCTAssertEqual(result.root.fileCount, 1_596_133)
        XCTAssertTrue(result.largestFiles.allSatisfy { $0.kind == .file })
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
            DiskEntry(url: URL(fileURLWithPath: path), kind: .directory,
                      allocatedBytes: children.reduce(0) { $0 + $1.allocatedBytes },
                      apparentBytes: children.reduce(0) { $0 + $1.apparentBytes },
                      fileCount: children.reduce(0) { $0 + $1.fileCount },
                      directoryCount: 1 + children.reduce(0) { $0 + $1.directoryCount },
                      modifiedAt: .distantPast, device: 1, inode: 1, children: children)
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

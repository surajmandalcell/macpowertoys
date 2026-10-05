import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

/// Offscreen captures of the Partition Manager window with a real attached disk image.
/// Attach a writable image first, for example: hdiutil create -size 2g -layout GPTSPUD -fs APFS x.dmg; hdiutil attach -nomount x.dmg.
final class PartitionManagerRenderTests: XCTestCase {
    @MainActor func testCapturesWindowWithAttachedImageDisk() throws {
        let disks = try DiskManagement.inventory()
        guard let image = disks.first(where: { $0.kind == .image && $0.protectionReason == nil }) else {
            throw XCTSkip("Attach a writable disk image to capture Partition Manager.")
        }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/redesign/captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = image.partitions.first { !$0.isEFI }
        let states: [(String, PartitionSelection, PartitionPreview?)] = [
            ("selected", target.map { .partition(disk: image.id, id: $0.id) } ?? .disk(image.id), nil),
            ("resize-preview", target.map { .partition(disk: image.id, id: $0.id) } ?? .disk(image.id),
             target.flatMap { $0.isAPFS ? .resize(partition: $0.id, size: $0.size * 6 / 10, split: true) : nil }),
            ("protected", .disk(disks.first { $0.kind == .internal }?.id ?? image.id), nil)
        ]
        let size = OnePlusWindowCanvas.diskExplorer.size
        for (state, selection, preview) in states {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let model = DiskManagementModel(disks: disks, selection: selection)
                model.preview = preview
                let priorAppearance = NSApp.appearance
                NSApp.appearance = NSAppearance(named: appearance)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let host = NSHostingView(rootView: DiskExplorerWindowView(model: model))
                let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: size.width, height: size.height),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                host.appearance = NSAppearance(named: appearance)
                window.contentView = host
                defer { NSApp.appearance = priorAppearance; window.close() }
                host.frame = CGRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("partition-\(state)-\(name).png"))
            }
        }
    }
}

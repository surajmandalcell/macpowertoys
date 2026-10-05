import XCTest
@testable import powertoys

final class DiskManagementTests: XCTestCase {
    private func list() -> [String: Any] {
        ["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk0", "Content": "GUID_partition_scheme", "Size": 500_277_792_768,
             "Partitions": [["DeviceIdentifier": "disk0s2", "Content": "Apple_APFS", "Size": 494_384_795_648]]],
            ["DeviceIdentifier": "disk3", "Content": "", "Size": 494_384_795_648,
             "APFSVolumes": [["DeviceIdentifier": "disk3s1s1", "MountPoint": "/", "VolumeName": "Macintosh HD"]]],
            ["DeviceIdentifier": "disk6", "Content": "GUID_partition_scheme", "Size": 1_000_204_886_016,
             "Partitions": [["DeviceIdentifier": "disk6s1", "Content": "EFI", "Size": 209_715_200, "VolumeName": "EFI"],
                            ["DeviceIdentifier": "disk6s2", "Content": "Apple_APFS", "Size": 999_995_129_856]]],
            ["DeviceIdentifier": "disk7", "Content": "", "Size": 999_995_129_856,
             "APFSVolumes": [["DeviceIdentifier": "disk7s1", "MountPoint": "/Volumes/External1TB", "VolumeName": "External1TB"]]],
            ["DeviceIdentifier": "disk16", "Content": "GUID_partition_scheme", "Size": 2_147_483_648,
             "Partitions": [["DeviceIdentifier": "disk16s1", "Content": "Apple_APFS", "Size": 1_000_000_000],
                            ["DeviceIdentifier": "disk16s2", "Content": "Microsoft Basic Data", "Size": 500_000_000,
                             "VolumeName": "PMEXFAT", "MountPoint": "/Volumes/PMEXFAT"]]],
            ["DeviceIdentifier": "disk17", "Content": "", "Size": 1_000_000_000,
             "APFSVolumes": [["DeviceIdentifier": "disk17s1", "MountPoint": "/Volumes/PMTEST", "VolumeName": "PMTEST"]]]
        ]]
    }
    private func apfs() -> [String: Any] {
        func container(_ reference: String, store: String, volume: String, name: String) -> [String: Any] {
            ["ContainerReference": reference, "CapacityCeiling": 1_000_000_000, "CapacityFree": 900_000_000,
             "PhysicalStores": [["DeviceIdentifier": store]],
             "Volumes": [["DeviceIdentifier": volume, "Name": name, "CapacityInUse": 100_000_000]]]
        }
        return ["Containers": [container("disk3", store: "disk0s2", volume: "disk3s1", name: "Macintosh HD"),
                               container("disk7", store: "disk6s2", volume: "disk7s1", name: "External1TB"),
                               container("disk17", store: "disk16s1", volume: "disk17s1", name: "PMTEST")]]
    }
    private func infos() -> [String: [String: Any]] {
        func whole(_ bus: String, internal isInternal: Bool, virtual: String, size: Int64, writable: Bool = true) -> [String: Any] {
            ["WholeDisk": true, "BusProtocol": bus, "Internal": isInternal, "VirtualOrPhysical": virtual, "Writable": writable,
             "RemovableMedia": bus == "Disk Image", "Content": "GUID_partition_scheme", "MediaName": bus == "Disk Image" ? "Disk Image" : "Drive",
             "SMARTStatus": bus == "Disk Image" ? "Not Supported" : "Verified", "Size": size]
        }
        return [
            "disk0": whole("Apple Fabric", internal: true, virtual: "Unknown", size: 500_277_792_768),
            "disk0s2": ["WholeDisk": false, "PartitionMapPartitionOffset": 524_312_576],
            "disk3": ["WholeDisk": true, "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]], "VirtualOrPhysical": "Virtual"],
            "disk6": whole("USB", internal: false, virtual: "Physical", size: 1_000_204_886_016),
            "disk6s1": ["WholeDisk": false, "PartitionMapPartitionOffset": 20480, "FilesystemType": "msdos"],
            "disk6s2": ["WholeDisk": false, "PartitionMapPartitionOffset": 209_735_680],
            "disk16": whole("Disk Image", internal: false, virtual: "Virtual", size: 2_147_483_648),
            "disk16s1": ["WholeDisk": false, "PartitionMapPartitionOffset": 20480],
            "disk16s2": ["WholeDisk": false, "PartitionMapPartitionOffset": 1_000_341_504, "FilesystemType": "exfat",
                         "FilesystemUserVisibleName": "ExFAT"],
            "disk17": ["WholeDisk": true, "APFSPhysicalStores": [["APFSPhysicalStore": "disk16s1"]], "BusProtocol": "Disk Image"]
        ]
    }
    private func parsed(protected: [String: String]? = ["disk0": "The startup disk is protected."]) -> [ManagedDisk] {
        DiskManagement.parseDisks(list: list(), apfs: apfs(), infos: infos(),
                                  imagePaths: ["disk16": "/tmp/test.dmg"], usage: ["disk16s2": 1_000_000],
                                  protected: protected, registryID: { _ in 1 })
    }

    func testParsingListsWholeDisksWithPartitionsVolumesAndFreeSpace() throws {
        let disks = parsed()
        XCTAssertEqual(disks.map(\.id), ["disk0", "disk6", "disk16"], "Synthesized APFS disks are not listed")
        let image = try XCTUnwrap(disks.last)
        XCTAssertEqual(image.kind, .image)
        XCTAssertEqual(image.schemeTitle, "GPT")
        XCTAssertEqual(image.imagePath, "/tmp/test.dmg")
        XCTAssertEqual(image.name, "test", "An image is named after its file")
        XCTAssertEqual(image.partitions.map(\.id), ["disk16s1", "disk16s2"])
        let container = image.partitions[0]
        XCTAssertEqual(container.apfsContainer, "disk17")
        XCTAssertEqual(container.volumes.map(\.name), ["PMTEST"])
        XCTAssertEqual(container.volumes.first?.mountPoint, "/Volumes/PMTEST")
        XCTAssertEqual(container.usedBytes, 100_000_000)
        let exfat = image.partitions[1]
        XCTAssertEqual(exfat.fileSystemType, "exfat")
        XCTAssertEqual(exfat.mountPoint, "/Volumes/PMEXFAT")
        XCTAssertEqual(exfat.usedBytes, 1_000_000)
        XCTAssertEqual(image.freeSpaces.count, 1)
        XCTAssertEqual(image.freeSpaces.first?.afterPartition, "disk16s2")
        XCTAssertEqual(image.freeSpaces.first?.offset, 1_500_341_504)
        XCTAssertNil(image.protectionReason)
        XCTAssertEqual(disks[0].partitions.first?.volumes.first?.mountPoint, "/", "A volume reports its mounted snapshot")
    }

    func testGuardProtectsStartupInternalReservedAndExternal1TBDisks() {
        let disks = parsed()
        XCTAssertNotNil(disks.first { $0.id == "disk0" }?.protectionReason)
        XCTAssertNotNil(disks.first { $0.id == "disk6" }?.protectionReason)
        let safe = DiskSafetyFacts(diskID: "disk16", isInternal: false, isWritable: true, protectedReason: nil,
                                   mountPoints: ["/Volumes/PMTEST"], imagePath: "/tmp/test.dmg")
        XCTAssertNil(DiskSafety.blockReason(safe))
        func facts(_ id: String = "disk16", internal isInternal: Bool = false, writable: Bool = true, reason: String? = nil,
                   mounts: [String] = [], image: String? = nil) -> DiskSafetyFacts {
            DiskSafetyFacts(diskID: id, isInternal: isInternal, isWritable: writable, protectedReason: reason,
                            mountPoints: mounts, imagePath: image)
        }
        XCTAssertNotNil(DiskSafety.blockReason(facts("disk6")))
        XCTAssertNotNil(DiskSafety.blockReason(facts("disk7")))
        XCTAssertNotNil(DiskSafety.blockReason(facts(), targets: ["disk7s1"]), "A target on disk7 is refused")
        XCTAssertNotNil(DiskSafety.blockReason(facts(), targets: ["disk6s2"]))
        XCTAssertNil(DiskSafety.blockReason(facts(), targets: ["disk60s1", "disk17"]), "disk60 is not disk6")
        XCTAssertNotNil(DiskSafety.blockReason(facts(mounts: ["/Volumes/External1TB"])))
        XCTAssertNotNil(DiskSafety.blockReason(facts(mounts: ["/Volumes/External1TB/dev"])))
        XCTAssertNil(DiskSafety.blockReason(facts(mounts: ["/Volumes/External1TB2"])))
        XCTAssertNotNil(DiskSafety.blockReason(facts(reason: "The startup disk is protected.")))
        XCTAssertNotNil(DiskSafety.blockReason(facts(internal: true)))
        XCTAssertNotNil(DiskSafety.blockReason(facts(writable: false)))
        XCTAssertNotNil(DiskSafety.blockReason(facts(image: "/System/Library/AssetsV2/runtime.dmg")))
        XCTAssertTrue(DiskManagement.isSystemImage("/Library/Developer/CoreSimulator/runtime.dmg"))
        XCTAssertFalse(DiskManagement.isSystemImage("/Users/me/Library/test.dmg"))
        XCTAssertNotNil(parsed(protected: nil).first { $0.id == "disk16" }?.protectionReason,
                        "Every disk is protected when protected disks cannot be resolved")
    }

    func testOperationsBuildExactDiskutilArguments() throws {
        let disk = try XCTUnwrap(parsed().last)
        XCTAssertEqual(try PartitionOperation.mount(target: "disk17").arguments(on: disk), ["mountDisk", "disk17"])
        XCTAssertEqual(try PartitionOperation.unmount(target: "disk16s2").arguments(on: disk), ["unmount", "disk16s2"])
        XCTAssertEqual(try PartitionOperation.rename(target: "disk16s2", name: "Photos").arguments(on: disk),
                       ["renameVolume", "disk16s2", "Photos"])
        XCTAssertEqual(try PartitionOperation.format(target: "disk16s2", fileSystem: .fat32, name: "card").arguments(on: disk),
                       ["eraseVolume", "FAT32", "CARD", "disk16s2"])
        XCTAssertEqual(try PartitionOperation.format(target: "disk16s1", fileSystem: .hfs, name: "Mac").arguments(on: disk),
                       ["apfs", "deleteContainer", "disk17", "JHFS+", "Mac", "0"])
        XCTAssertEqual(try PartitionOperation.delete(target: "disk16s2").arguments(on: disk), ["eraseVolume", "free", "free", "disk16s2"])
        XCTAssertEqual(try PartitionOperation.delete(target: "disk16s1").arguments(on: disk), ["apfs", "deleteContainer", "disk17"])
        XCTAssertEqual(try PartitionOperation.create(after: "disk16s2", fileSystem: .exfat, name: "New", size: nil).arguments(on: disk),
                       ["addPartition", "disk16s2", "ExFAT", "New", "0"])
        XCTAssertEqual(try PartitionOperation.resize(target: "disk16s1", size: 800_000_000,
                                                     split: PartitionSplit(fileSystem: .hfs, name: "Split")).arguments(on: disk),
                       ["apfs", "resizeContainer", "disk16s1", "800000000B", "JHFS+", "Split", "0"])
        XCTAssertEqual(try PartitionOperation.eraseDisk(fileSystem: .exfat, name: "Card", scheme: .mbr).arguments(on: disk),
                       ["eraseDisk", "ExFAT", "Card", "MBR", "disk16"])
        XCTAssertEqual(try PartitionOperation.verify(target: nil).arguments(on: disk), ["verifyDisk", "disk16"])
        XCTAssertThrowsError(try PartitionOperation.eraseDisk(fileSystem: .apfs, name: "Card", scheme: .mbr).arguments(on: disk))
        XCTAssertThrowsError(try PartitionOperation.repair(target: nil).arguments(on: disk), "Whole-disk repair can prompt")
        XCTAssertThrowsError(try PartitionOperation.resize(target: "disk16s2", size: 400_000_000, split: nil).arguments(on: disk),
                             "ExFAT cannot be resized")
        XCTAssertThrowsError(try PartitionOperation.rename(target: "disk6s2", name: "X").arguments(on: disk), "Targets stay on this disk")
        XCTAssertThrowsError(try PartitionOperation.format(target: "disk16s2", fileSystem: .fat32, name: "TWELVECHARSX").arguments(on: disk))
        XCTAssertThrowsError(try PartitionOperation.rename(target: "disk16s2", name: "a/b").arguments(on: disk))
        XCTAssertTrue(PartitionOperation.delete(target: "disk16s2").isDestructive)
        XCTAssertFalse(PartitionOperation.mount(target: "disk17").isWrite)
        XCTAssertTrue(PartitionOperation.eject.isWrite)
    }

    func testMapLayoutKeepsSmallBlocksVisibleAndPreviewsChanges() throws {
        let widths = PartitionMapLayout.widths([200_000_000, 999_000_000_000, 1_000_000_000], available: 600, minimum: 56, spacing: 4)
        XCTAssertEqual(widths.reduce(0, +), 592, accuracy: 0.01)
        XCTAssertEqual(widths[0], 56, accuracy: 0.01)
        XCTAssertEqual(widths[2], 56, accuracy: 0.01)
        XCTAssertGreaterThan(widths[1], 400)
        XCTAssertEqual(PartitionMapLayout.widths([1, 1], available: .nan, minimum: 56, spacing: 4), [0, 0])

        let disk = try XCTUnwrap(parsed().last)
        XCTAssertEqual(PartitionMapLayout.segments(for: disk).map(\.id), ["disk16s1", "disk16s2", "free-disk16-disk16s2"])
        let created = PartitionMapLayout.segments(for: disk, preview: .create(free: "free-disk16-disk16s2", size: 200_000_000))
        XCTAssertEqual(created.map(\.id), ["disk16s1", "disk16s2", "pending", "free-disk16-disk16s2"])
        XCTAssertEqual(created.map(\.bytes).reduce(0, +), PartitionMapLayout.segments(for: disk).map(\.bytes).reduce(0, +))
        let shrunk = PartitionMapLayout.segments(for: disk, preview: .resize(partition: "disk16s1", size: 600_000_000, split: false))
        XCTAssertEqual(shrunk.map(\.id), ["disk16s1", "free-disk16-disk16s1", "disk16s2", "free-disk16-disk16s2"])
        XCTAssertEqual(shrunk[0].bytes, 600_000_000)
        XCTAssertEqual(shrunk[1].bytes, 400_000_000)
        let split = PartitionMapLayout.segments(for: disk, preview: .resize(partition: "disk16s1", size: 600_000_000, split: true))
        XCTAssertEqual(split[1].id, "pending")
    }

    func testActionsExplainWhyTheyAreUnavailable() throws {
        let disks = parsed()
        let image = try XCTUnwrap(disks.last)
        let startup = try XCTUnwrap(disks.first)
        func reason(_ action: PartitionAction, _ selection: PartitionSelection, _ disk: ManagedDisk) -> String? {
            PartitionAction.unavailableReason(action, selection: selection, disk: disk)
        }
        XCTAssertNotNil(reason(.eraseDisk, .disk("disk0"), startup))
        XCTAssertNotNil(reason(.format, .partition(disk: "disk0", id: "disk0s2"), startup))
        XCTAssertNil(reason(.info, .disk("disk0"), startup))
        XCTAssertNil(reason(.eraseDisk, .disk("disk16"), image))
        XCTAssertNil(reason(.format, .partition(disk: "disk16", id: "disk16s2"), image))
        XCTAssertNotNil(reason(.resize, .partition(disk: "disk16", id: "disk16s2"), image), "ExFAT cannot be resized")
        XCTAssertNil(reason(.resize, .partition(disk: "disk16", id: "disk16s1"), image))
        XCTAssertNil(reason(.create, .free(disk: "disk16", id: "free-disk16-disk16s2"), image))
        XCTAssertNotNil(reason(.create, .partition(disk: "disk16", id: "disk16s2"), image))
        XCTAssertNotNil(reason(.mount, .partition(disk: "disk16", id: "disk16s2"), image), "Already mounted")
        XCTAssertNil(reason(.unmount, .partition(disk: "disk16", id: "disk16s2"), image))
        XCTAssertNil(reason(.rename, .partition(disk: "disk16", id: "disk16s1"), image), "A one-volume container renames its volume")
        XCTAssertNotNil(reason(.format, .volume(disk: "disk16", partition: "disk16s1", id: "disk17s1"), image))
        XCTAssertNotNil(reason(.firstAid, .disk("disk16"), image), "macOS refuses a GPT disk without EFI")
        let efi = try XCTUnwrap(disks.first { $0.id == "disk6" })
        XCTAssertNotNil(reason(.delete, .partition(disk: "disk6", id: "disk6s1"), efi))
    }

    @MainActor func testSelectionFollowsAPartitionWhoseIdentifierChanged() throws {
        let disk = try XCTUnwrap(parsed().last)
        let model = DiskManagementModel(disks: [disk], selection: .partition(disk: "disk16", id: "disk16s2"), isPreview: true)
        let moved = ManagedPartition(id: "disk16s3", name: "PMFAT", content: "Microsoft Basic Data", offset: 1_000_341_504,
                                     size: 500_000_000, fileSystemType: "msdos")
        let renumbered = ManagedDisk(id: disk.id, name: disk.name, size: disk.size, bus: disk.bus, scheme: disk.scheme, kind: disk.kind,
                                     writable: true, smart: nil, imagePath: nil, mediaRegistryID: 1,
                                     partitions: [disk.partitions[0], moved], protectionReason: nil)
        model.update([renumbered], keepingOffset: 1_000_341_504)
        XCTAssertEqual(model.selection, .partition(disk: "disk16", id: "disk16s3"))
        model.update([])
        XCTAssertNil(model.selection)
    }

    func testBlockedEjectParsesProcessesAndRejectsProtectedQuit() {
        XCTAssertEqual(DiskManagement.parseLsofProcesses("p42\ncPreview\np7\ncFinder\n").map(\.0), [42, 7])
        XCTAssertFalse(DiskEjectBlocker(pid: 7, name: "Finder", started: 1, userID: geteuid()).canQuit)
        XCTAssertFalse(DiskEjectBlocker(pid: getpid(), name: "Tool", started: 1, userID: geteuid()).canQuit)
        XCTAssertTrue(DiskEjectBlocker(pid: 42, name: "Preview", started: 1, userID: geteuid()).canQuit)
    }
}

//
//  AppDataLocation.swift
//  powertoys
//

import Foundation

enum AppDataLocation {
    static var directory: URL {
        let folderName = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            ? "PowerToys-Tests"
            : "PowerToys"
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var storeURL: URL {
        directory.appendingPathComponent("PowerToys.store")
    }

    static var transfersURL: URL {
        directory.appendingPathComponent("transfers.json")
    }

    static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: storeURL.path) else { return }

        let legacyDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard fm.fileExists(atPath: legacyDirectory.appendingPathComponent("default.store").path) else { return }

        for suffix in ["", "-shm", "-wal"] {
            let source = legacyDirectory.appendingPathComponent("default.store" + suffix)
            let destination = directory.appendingPathComponent("PowerToys.store" + suffix)
            if fm.fileExists(atPath: source.path) {
                try? fm.copyItem(at: source, to: destination)
            }
        }
    }
}

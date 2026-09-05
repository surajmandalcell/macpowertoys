//
//  AppDataLocation.swift
//  powertoys
//

import Foundation
import AppKit

nonisolated enum AppDataLocation {
    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return prepareDirectory(
            at: root,
            isTest: AppRuntime.isRunningTests
        )
    }

    static var storeURL: URL {
        directory.appendingPathComponent("MacPowerToys.store")
    }

    static var transfersURL: URL {
        directory.appendingPathComponent("transfers.json")
    }

    static var localChangesURL: URL {
        directory.appendingPathComponent("local-changes.json")
    }

    static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: storeURL.path) else { return }

        let legacyDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard fm.fileExists(atPath: legacyDirectory.appendingPathComponent("default.store").path) else { return }

        for suffix in ["", "-shm", "-wal"] {
            let source = legacyDirectory.appendingPathComponent("default.store" + suffix)
            let destination = directory.appendingPathComponent("MacPowerToys.store" + suffix)
            if fm.fileExists(atPath: source.path) {
                try? fm.copyItem(at: source, to: destination)
            }
        }
    }

    @discardableResult
    static func prepareDirectory(at root: URL, isTest: Bool) -> URL {
        let fm = FileManager.default
        let destinationName = isTest ? "MacPowerToys-Tests" : "MacPowerToys"
        let legacyName = isTest ? "PowerToys-Tests" : "PowerToys"
        let destination = root.appendingPathComponent(destinationName, isDirectory: true)
        let legacy = root.appendingPathComponent(legacyName, isDirectory: true)

        if !fm.fileExists(atPath: destination.path), fm.fileExists(atPath: legacy.path) {
            try? fm.copyItem(at: legacy, to: destination)
        }
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for suffix in ["", "-shm", "-wal"] {
            let current = destination.appendingPathComponent("MacPowerToys.store" + suffix)
            let old = destination.appendingPathComponent("PowerToys.store" + suffix)
            if !fm.fileExists(atPath: current.path), fm.fileExists(atPath: old.path) {
                try? fm.copyItem(at: old, to: current)
            }
        }
        return destination
    }
}

enum AppIdentity {
    static let displayName = "MacPowerToys"
    nonisolated static let bundleIdentifier = "com.surajmandal.macpowertoys"
    nonisolated static let legacyBundleIdentifier = "com.surajmandal.powertoys"
    private static let defaultsMigrationKey = "app.identityMigratedFromPowerToys"

    static var isLegacyAppRunning: Bool {
        hasLegacyApp(in: NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
    }

    nonisolated static func hasLegacyApp(in bundleIdentifiers: [String?]) -> Bool {
        bundleIdentifiers.contains(legacyBundleIdentifier)
    }

    static func migrateLegacyData() {
        _ = AppDataLocation.directory
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsMigrationKey) else { return }
        let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier) ?? [:]
        _ = migrateLegacyDefaults(legacy, into: defaults)
        defaults.set(true, forKey: defaultsMigrationKey)
    }

    @discardableResult
    static func migrateLegacyDefaults(_ legacy: [String: Any], into defaults: UserDefaults) -> Int {
        var copied = 0
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        return copied
    }
}

//
//  SettingsSyncManager.swift
//  powertoys
//

import Foundation

protocol KeyValueCloudStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
    var dictionaryRepresentation: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueCloudStore {}

extension Notification.Name {
    static let marketplaceSourcesChanged = Notification.Name("marketplaceSourcesChanged")
    static let marketplaceReceiptsChanged = Notification.Name("marketplaceReceiptsChanged")
}

@Observable
@MainActor
final class SettingsSyncManager {
    static let shared = SettingsSyncManager()

    enum EnableResult {
        case enabled
        case conflict
    }

    static let syncedDefaultsKeys: [String] = [
        "appTheme",
        "app.showTray",
        "cchistory.autoRefresh",
        "cchistory.deepSearchDefault",
        "logs.fontSize"
    ]
    static let sourceListKey = "marketplace.sourceURLs"
    static let seedMarkerKey = "settingsSync.seededAt"
    static let enabledDefaultsKey = "settingsSync.enabled"
    private static let defaultsKeyPrefix = "defaults."
    private static let toolKeyPrefix = "tool."

    private let cloud: KeyValueCloudStore
    private let defaults: UserDefaults
    private let currentSourceURLs: @MainActor () -> [String]
    private let applySourceURLs: @MainActor ([String]) -> Void
    private let receiptsProvider: @MainActor () -> [MarketplaceReceipt]
    private let readToolPreference: (String, String) -> Any?
    private let writeToolPreference: (String, String, Any) -> Void

    private(set) var isEnabled: Bool
    private(set) var isActive = false
    private(set) var lastSyncDescription: String?
    private var isApplyingRemote = false
    private var observers: [NSObjectProtocol] = []

    init(
        cloud: KeyValueCloudStore = NSUbiquitousKeyValueStore.default,
        defaults: UserDefaults = .standard,
        currentSourceURLs: @escaping @MainActor () -> [String] = {
            MarketplaceManager.shared.sources.map(\.url.absoluteString)
        },
        applySourceURLs: @escaping @MainActor ([String]) -> Void = { urls in
            Task { await MarketplaceManager.shared.applySyncedSourceURLs(urls) }
        },
        receiptsProvider: @escaping @MainActor () -> [MarketplaceReceipt] = { MarketplaceManager.shared.receipts },
        readToolPreference: @escaping (String, String) -> Any? = { bundleID, key in
            CFPreferencesCopyAppValue(key as CFString, bundleID as CFString)
        },
        writeToolPreference: @escaping (String, String, Any) -> Void = { bundleID, key, value in
            CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, bundleID as CFString)
            CFPreferencesAppSynchronize(bundleID as CFString)
        }
    ) {
        self.cloud = cloud
        self.defaults = defaults
        self.currentSourceURLs = currentSourceURLs
        self.applySourceURLs = applySourceURLs
        self.receiptsProvider = receiptsProvider
        self.readToolPreference = readToolPreference
        self.writeToolPreference = writeToolPreference
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    // MARK: - Lifecycle

    func startIfEnabled() {
        guard isEnabled else { return }
        activate()
        applyCloudKeys(Array(cloud.dictionaryRepresentation.keys))
        pushAll(includeSourceList: false)
    }

    func enable() -> EnableResult {
        cloud.synchronize()
        guard cloud.object(forKey: Self.seedMarkerKey) == nil else {
            return .conflict
        }
        setEnabled(true)
        activate()
        pushAll()
        return .enabled
    }

    func resolveConflict(useCloud: Bool) {
        setEnabled(true)
        activate()
        if useCloud {
            applyCloudKeys(Array(cloud.dictionaryRepresentation.keys))
            pushAll(includeSourceList: false)
        } else {
            pushAll()
        }
    }

    func disable() {
        setEnabled(false)
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        isActive = false
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud as AnyObject,
            queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.applyCloudKeys(keys) }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushLocalDefaults() }
        })
        observers.append(center.addObserver(
            forName: .marketplaceSourcesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushSourceList() }
        })
        observers.append(center.addObserver(
            forName: .marketplaceReceiptsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushToolContracts() }
        })
    }

    // MARK: - Push

    private func pushAll(includeSourceList: Bool = true) {
        pushLocalDefaults()
        if includeSourceList {
            pushSourceList()
        }
        pushToolContracts()
        compareAndSet(Date().timeIntervalSince1970, cloudKey: Self.seedMarkerKey, onlyIfAbsent: true)
        cloud.synchronize()
    }

    private func pushLocalDefaults() {
        guard isActive, !isApplyingRemote else { return }
        for key in Self.syncedDefaultsKeys {
            compareAndSet(defaults.object(forKey: key), cloudKey: Self.defaultsKeyPrefix + key)
        }
        cloud.synchronize()
    }

    private func pushSourceList() {
        guard isActive, !isApplyingRemote else { return }
        compareAndSet(currentSourceURLs(), cloudKey: Self.sourceListKey)
        cloud.synchronize()
    }

    private func pushToolContracts() {
        guard isActive, !isApplyingRemote else { return }
        for receipt in receiptsProvider() {
            guard let contract = receipt.settingsSync else { continue }
            for key in contract.keys {
                guard let value = readToolPreference(receipt.bundleID, key) else { continue }
                compareAndSet(value, cloudKey: "\(Self.toolKeyPrefix)\(receipt.bundleID)/\(key)")
            }
        }
        cloud.synchronize()
    }

    private func compareAndSet(_ value: Any?, cloudKey: String, onlyIfAbsent: Bool = false) {
        let existing = cloud.object(forKey: cloudKey)
        if onlyIfAbsent, existing != nil { return }
        guard !Self.plistEqual(existing, value) else { return }
        if let value {
            cloud.set(value, forKey: cloudKey)
        } else {
            cloud.removeObject(forKey: cloudKey)
        }
    }

    // MARK: - Apply

    private func applyCloudKeys(_ keys: [String]) {
        guard isActive else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        var applied = 0
        for key in keys {
            if key == Self.sourceListKey {
                if let urls = cloud.object(forKey: key) as? [String] {
                    applySourceURLs(urls)
                    applied += 1
                }
            } else if key.hasPrefix(Self.defaultsKeyPrefix) {
                let defaultsKey = String(key.dropFirst(Self.defaultsKeyPrefix.count))
                guard Self.syncedDefaultsKeys.contains(defaultsKey) else { continue }
                let value = cloud.object(forKey: key)
                guard !Self.plistEqual(defaults.object(forKey: defaultsKey), value) else { continue }
                if let value {
                    defaults.set(value, forKey: defaultsKey)
                } else {
                    defaults.removeObject(forKey: defaultsKey)
                }
                applied += 1
            } else if key.hasPrefix(Self.toolKeyPrefix) {
                applied += applyToolPreference(cloudKey: key) ? 1 : 0
            }
        }
        if applied > 0 {
            lastSyncDescription = "Applied \(applied) change\(applied == 1 ? "" : "s") from iCloud"
        }
    }

    private func applyToolPreference(cloudKey: String) -> Bool {
        let rest = cloudKey.dropFirst(Self.toolKeyPrefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return false }
        let bundleID = String(rest[..<slash])
        let prefKey = String(rest[rest.index(after: slash)...])
        guard let receipt = receiptsProvider().first(where: { $0.bundleID == bundleID }),
              receipt.settingsSync?.keys.contains(prefKey) == true,
              let value = cloud.object(forKey: cloudKey)
        else { return false }
        writeToolPreference(bundleID, prefKey, value)
        return true
    }

    private nonisolated static func plistEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            true
        case let (l?, r?):
            (l as AnyObject).isEqual(r)
        default:
            false
        }
    }
}

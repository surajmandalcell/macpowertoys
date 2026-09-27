import CoreFoundation
import Foundation

struct TweakChoice {
    let label: String
    let value: Any
}

struct TweakPreferenceField {
    let label: String
    let domain: String
    let key: String
    let choices: [TweakChoice]
    let defaultLabel: String?

    init(
        label: String,
        domain: String,
        key: String,
        choices: [TweakChoice],
        defaultLabel: String? = nil
    ) {
        self.label = label
        self.domain = domain
        self.key = key
        self.choices = choices
        self.defaultLabel = defaultLabel
    }

    var identity: String { "\(domain)/\(key)" }

    static func flag(
        _ label: String,
        _ domain: String,
        _ key: String,
        default defaultValue: Bool? = nil
    ) -> Self {
        .init(label: label, domain: domain, key: key,
              choices: [.init(label: "On", value: true), .init(label: "Off", value: false)],
              defaultLabel: defaultValue.map { $0 ? "On" : "Off" })
    }
}

enum TweakPreferences {
    private static let dock = "com.apple.dock"
    private static let finder = "com.apple.finder"
    private static let global = ".GlobalPreferences"
    private static let capture = "com.apple.screencapture"

    static func supportsWrites(for id: String, on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        guard (version.majorVersion == 15 && version.minorVersion == 8) ||
              (version.majorVersion == 26 && version.minorVersion == 7) ||
              (version.majorVersion == 27 && version.minorVersion == 0) else { return false }
        if id == "finder.column-sizing" || id == "apps.automatic-termination" {
            return version.majorVersion == 15
        }
        return !fields(for: id).isEmpty
    }

    static func fields(for id: String) -> [TweakPreferenceField] {
        switch id {
        case "dock.reveal-delay": return [seconds("Reveal delay", dock, "autohide-delay", default: 0.40)]
        case "dock.animation-duration": return [seconds("Hide / show duration", dock, "autohide-time-modifier", default: 0.35)]
        case "dock.hidden-app-dimming": return [.flag("Dim hidden apps", dock, "showhidden", default: false)]
        case "dock.lock-size": return [.flag("Lock Dock icon size", dock, "size-immutable", default: false)]
        case "dock.lock-contents": return [.flag("Lock Dock layout", dock, "contents-immutable", default: false)]
        case "dock.stack-selection": return [.flag("Highlight stack selection", dock, "mouse-over-hilite-stack", default: false)]
        case "dock.minimize-effect": return [.init(label: "Minimize effect", domain: dock, key: "mineffect",
                                                  choices: [.init(label: "Suck", value: "suck"), .init(label: "Genie", value: "genie"), .init(label: "Scale", value: "scale")],
                                                  defaultLabel: "Genie")]
        case "dock.slow-motion": return [.flag("Shift slow motion", dock, "slow-motion-allowed", default: false)]
        case "dock.switcher-displays": return [.flag("Cmd-Tab on every display", dock, "appswitcher-all-displays", default: false)]
        case "finder.hidden-files": return [.flag("Show hidden files", finder, "AppleShowAllFiles", default: false)]
        case "finder.quit": return [.flag("Quit Finder menu item", finder, "QuitMenuItem", default: false)]
        case "finder.path-title": return [.flag("Full path in the title bar", finder, "_FXShowPosixPathInTitle", default: false)]
        case "finder.sounds": return [.flag("Finder sounds", finder, "FinderSounds", default: true)]
        case "finder.network-metadata": return [.flag("Avoid metadata on network shares", "com.apple.desktopservices", "DSDontWriteNetworkStores", default: false)]
        case "input.press-hold": return [.init(
            label: "Repeat instead of accents", domain: global, key: "ApplePressAndHoldEnabled",
            choices: [.init(label: "On", value: false), .init(label: "Off", value: true)],
            defaultLabel: "Off"
        )]
        case "dialogs.expanded-save": return [
            .flag("Expanded Save panels", global, "NSNavPanelExpandedStateForSaveMode", default: true),
            .flag("Expanded alternate Save panels", global, "NSNavPanelExpandedStateForSaveMode2", default: true)
        ]
        case "windows.scroll-animation": return [.flag("Page-scroll animation", global, "NSScrollAnimationEnabled", default: true)]
        case "menubar.spacing": return [
            points("Item spacing", global, "NSStatusItemSpacing", [2, 4, 6, 8, 10, 12, 14, 16]),
            points("Selection padding", global, "NSStatusItemSelectionPadding", [2, 4, 6, 8, 10, 12, 14, 16])
        ]
        case "screenshots.format": return [.init(label: "Image format", domain: capture, key: "type",
                                                  choices: ["png", "jpg", "pdf", "tiff"].map { .init(label: $0.uppercased(), value: $0) },
                                                  defaultLabel: "PNG")]
        case "screenshots.shadow": return [.init(
            label: "Include window shadows", domain: capture, key: "disable-shadow",
            choices: [.init(label: "On", value: false), .init(label: "Off", value: true)],
            defaultLabel: "On"
        )]
        case "screenshots.date": return [.flag("Timestamp in filename", capture, "include-date", default: true)]
        case "terminal.pointer-focus": return [.flag("Terminal pointer focus", "com.apple.Terminal", "FocusFollowsMouse", default: false)]
        case "music.half-stars": return [.flag("Half-star ratings", "com.apple.Music", "allow-half-stars", default: false)]
        case "finder.column-sizing":
            return [.flag("Automatic column width", finder, "_FXEnableColumnAutoSizing", default: false)]
        case "apps.automatic-termination":
            return [.flag("Keep unused apps open", global, "NSDisableAutomaticTermination", default: false)]
        default: return []
        }
    }

    private static func seconds(
        _ label: String,
        _ domain: String,
        _ key: String,
        default defaultValue: Double
    ) -> TweakPreferenceField {
        let values = (0...60).map { Double($0) * 0.05 }
        return .init(label: label, domain: domain, key: key,
                     choices: values.map { .init(label: String(format: "%.2f seconds", $0), value: $0) },
                     defaultLabel: String(format: "%.2f seconds", defaultValue))
    }

    private static func points(_ label: String, _ domain: String, _ key: String, _ values: [Int]) -> TweakPreferenceField {
        .init(label: label, domain: domain, key: key,
              choices: values.map { .init(label: "\($0) points", value: $0) })
    }
}

enum TweakPreferenceError: LocalizedError {
    case managed(String)
    case changedElsewhere(String)
    case writeFailed(String)
    case invalidSelection
    case screenshotConflict

    var errorDescription: String? {
        switch self {
        case .managed(let key): "\(key) is managed by your Mac's administrator."
        case .changedElsewhere(let key): "\(key) changed outside Mac Tweaks. Review its current value before changing it."
        case .writeFailed(let domain): "Could not save preferences in \(domain). Try again after checking file permissions."
        case .invalidSelection: "Choose a valid setting before applying."
        case .screenshotConflict: "Turn off the floating thumbnail in Screenshot before selecting PDF on Tahoe."
        }
    }
}

final class TweakPreferenceStore {
    static let shared = TweakPreferenceStore()

    private struct StoredValue: Codable, Equatable {
        let data: Data?
    }

    private struct Record: Codable {
        let original: Data?
        var lastWritten: Data?
        var pending: StoredValue?

        init(original: Data?, lastWritten: Data?, pending: StoredValue? = nil) {
            self.original = original
            self.lastWritten = lastWritten
            self.pending = pending
        }
    }

    private let backupKey = "macTweaks.preferenceBackups.v1"
    private let defaults: UserDefaults
    private var records: [String: Record]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: backupKey) ?? Data()
        records = (try? PropertyListDecoder().decode([String: Record].self, from: data)) ?? [:]
    }

    func value(for field: TweakPreferenceField) -> Any? {
        CFPreferencesCopyValue(field.key as CFString, domainID(field.domain),
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func selectedChoice(for field: TweakPreferenceField) -> Int {
        try? reconcilePendingWrite(for: field)
        guard let current = value(for: field), let data = archive(current) else { return -1 }
        return field.choices.firstIndex { archive($0.value) == data } ?? -2
    }

    func hasBackup(for fields: [TweakPreferenceField]) -> Bool {
        for field in fields { try? reconcilePendingWrite(for: field) }
        return fields.contains { records[$0.identity] != nil }
    }

    func isModified(_ field: TweakPreferenceField) -> Bool {
        try? reconcilePendingWrite(for: field)
        return records[field.identity] != nil
    }

    func originalChoice(for field: TweakPreferenceField) -> Int? {
        try? reconcilePendingWrite(for: field)
        guard let record = records[field.identity] else { return nil }
        guard let original = record.original else { return -1 }
        return field.choices.firstIndex { archive($0.value) == original } ?? -2
    }

    func apply(_ fields: [TweakPreferenceField], selections: [String: Int]) throws {
        for field in fields { try reconcilePendingWrite(for: field) }
        let originalRecords = records
        var next = records
        var writes: [(TweakPreferenceField, Any?)] = []
        var before: [(TweakPreferenceField, Any?)] = []
        for field in fields {
            guard let selection = selections[field.identity], selection >= -1, selection < field.choices.count else {
                throw TweakPreferenceError.invalidSelection
            }
            if defaults.objectIsForced(forKey: field.key, inDomain: field.domain) {
                throw TweakPreferenceError.managed(field.key)
            }
            if field.domain == "com.apple.screencapture", field.key == "type", selection >= 0,
               field.choices[selection].value as? String == "pdf",
               ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 {
                let thumbnail = CFPreferencesCopyAppValue("show-thumbnail" as CFString, field.domain as CFString) as? Bool ?? true
                if thumbnail { throw TweakPreferenceError.screenshotConflict }
            }
            let current = value(for: field)
            let currentData = current.flatMap(archive)
            if let previous = next[field.identity], previous.lastWritten != currentData {
                throw TweakPreferenceError.changedElsewhere(field.key)
            }
            let chosen: Any? = selection == -1 ? nil : field.choices[selection].value
            let chosenData = chosen.flatMap(archive)
            guard chosenData != currentData else { continue }
            var record = next[field.identity] ?? Record(original: currentData, lastWritten: currentData)
            record.pending = StoredValue(data: chosenData)
            next[field.identity] = record
            before.append((field, current))
            writes.append((field, chosen))
        }
        guard !writes.isEmpty else { return }
        try persist(next)
        records = next
        for (field, chosen) in writes { set(chosen, for: field) }
        do {
            try synchronizeAndCheck(writes)
            var committed = next
            for (field, _) in writes {
                guard var record = committed[field.identity], let pending = record.pending else { continue }
                if pending.data == record.original {
                    committed.removeValue(forKey: field.identity)
                } else {
                    record.lastWritten = pending.data
                    record.pending = nil
                    committed[field.identity] = record
                }
            }
            try persist(committed)
            records = committed
        } catch {
            for (field, oldValue) in before { set(oldValue, for: field) }
            do {
                try synchronizeAndCheck(before)
                try persist(originalRecords)
                records = originalRecords
            } catch {
                records = next
            }
            throw error
        }
    }

    func restore(_ fields: [TweakPreferenceField]) throws {
        for field in fields { try reconcilePendingWrite(for: field) }
        var writes: [(TweakPreferenceField, Any?)] = []
        var before: [(TweakPreferenceField, Any?)] = []
        var cleared: [String] = []
        for field in fields {
            guard let record = records[field.identity] else { continue }
            let current = value(for: field)
            let currentData = current.flatMap(archive)
            if currentData == record.original {
                cleared.append(field.identity)
                continue
            }
            guard record.lastWritten == currentData else {
                throw TweakPreferenceError.changedElsewhere(field.key)
            }
            before.append((field, current))
            writes.append((field, record.original.flatMap(unarchive)))
            cleared.append(field.identity)
        }
        guard !cleared.isEmpty else { return }
        for (field, value) in writes { set(value, for: field) }
        do {
            try synchronizeAndCheck(writes)
            var next = records
            for identity in cleared { next.removeValue(forKey: identity) }
            try persist(next)
            records = next
        } catch {
            for (field, previous) in before { set(previous, for: field) }
            try? synchronizeAndCheck(before)
            throw error
        }
    }

    private func set(_ value: Any?, for field: TweakPreferenceField) {
        CFPreferencesSetValue(field.key as CFString, value as CFPropertyList?, domainID(field.domain),
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func synchronizeAndCheck(_ writes: [(TweakPreferenceField, Any?)]) throws {
        for domain in Set(writes.map { $0.0.domain }) {
            guard CFPreferencesSynchronize(domainID(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
                throw TweakPreferenceError.writeFailed(domain)
            }
        }
        for (field, expected) in writes where value(for: field).flatMap(archive) != expected.flatMap(archive) {
            throw TweakPreferenceError.writeFailed(field.domain)
        }
    }

    private func domainID(_ domain: String) -> CFString {
        domain == ".GlobalPreferences" ? kCFPreferencesAnyApplication : domain as CFString
    }

    private func archive(_ value: Any) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
    }

    private func unarchive(_ data: Data) -> Any? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])?["value"]
    }

    private func reconcilePendingWrite(for field: TweakPreferenceField) throws {
        guard var record = records[field.identity] else { return }
        let currentData = value(for: field).flatMap(archive)
        var next = records
        if currentData == record.original {
            next.removeValue(forKey: field.identity)
            try persist(next)
            records = next
            return
        }
        guard let pending = record.pending else { return }
        if currentData == pending.data {
            record.lastWritten = currentData
            record.pending = nil
            next[field.identity] = record
        } else {
            record.pending = nil
            next[field.identity] = record
        }
        try persist(next)
        records = next
    }

    private func persist(_ records: [String: Record]) throws {
        guard let data = try? PropertyListEncoder().encode(records) else {
            throw TweakPreferenceError.writeFailed("Mac Tweaks backup")
        }
        defaults.set(data, forKey: backupKey)
        guard defaults.synchronize() else { throw TweakPreferenceError.writeFailed("Mac Tweaks backup") }
    }
}

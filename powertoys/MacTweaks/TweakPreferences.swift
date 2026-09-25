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

    var identity: String { "\(domain)/\(key)" }

    static func flag(_ label: String, _ domain: String, _ key: String) -> Self {
        .init(label: label, domain: domain, key: key,
              choices: [.init(label: "On", value: true), .init(label: "Off", value: false)])
    }
}

enum TweakPreferences {
    private static let dock = "com.apple.dock"
    private static let finder = "com.apple.finder"
    private static let global = ".GlobalPreferences"
    private static let capture = "com.apple.screencapture"

    static func fields(for id: String) -> [TweakPreferenceField] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard (version.majorVersion == 15 && version.minorVersion == 8) ||
              (version.majorVersion == 26 && version.minorVersion == 7) ||
              (version.majorVersion == 27 && version.minorVersion == 0) else { return [] }
        switch id {
        case "dock.reveal-delay": return [seconds("Reveal delay", dock, "autohide-delay", [0, 0.2, 0.5, 1, 2])]
        case "dock.animation-duration": return [seconds("Animation duration", dock, "autohide-time-modifier", [0, 0.2, 0.5, 1, 2])]
        case "dock.hidden-app-dimming": return [.flag("Dim hidden applications", dock, "showhidden")]
        case "dock.lock-size": return [.flag("Lock icon size", dock, "size-immutable")]
        case "dock.lock-contents": return [.flag("Lock item arrangement", dock, "contents-immutable")]
        case "dock.stack-selection": return [.flag("Highlight hovered item", dock, "mouse-over-hilite-stack")]
        case "dock.minimize-effect": return [.init(label: "Minimize effect", domain: dock, key: "mineffect",
                                                  choices: [.init(label: "Suck", value: "suck"), .init(label: "Genie", value: "genie"), .init(label: "Scale", value: "scale")])]
        case "dock.slow-motion": return [.flag("Shift slow motion", dock, "slow-motion-allowed")]
        case "dock.switcher-displays": return [.flag("Show on every display", dock, "appswitcher-all-displays")]
        case "finder.hidden-files": return [.flag("Show hidden files", finder, "AppleShowAllFiles")]
        case "finder.quit": return [.flag("Show Quit Finder", finder, "QuitMenuItem")]
        case "finder.path-title": return [.flag("Show full path in title", finder, "_FXShowPosixPathInTitle")]
        case "finder.sounds": return [.flag("Play Finder sounds", finder, "FinderSounds")]
        case "finder.network-metadata": return [.flag("Avoid .DS_Store on network shares", "com.apple.desktopservices", "DSDontWriteNetworkStores")]
        case "input.press-hold": return [.flag("Show accents on key hold", global, "ApplePressAndHoldEnabled")]
        case "dialogs.expanded-save": return [
            .flag("Expand Save panels", global, "NSNavPanelExpandedStateForSaveMode"),
            .flag("Expand alternate Save panels", global, "NSNavPanelExpandedStateForSaveMode2")
        ]
        case "windows.scroll-animation": return [.flag("Animate native page scrolling", global, "NSScrollAnimationEnabled")]
        case "menubar.spacing": return [
            points("Item spacing", global, "NSStatusItemSpacing", [2, 4, 6, 8, 10, 12, 14, 16]),
            points("Selection padding", global, "NSStatusItemSelectionPadding", [2, 4, 6, 8, 10, 12, 14, 16])
        ]
        case "screenshots.format": return [.init(label: "Capture format", domain: capture, key: "type",
                                                  choices: ["png", "jpg", "pdf", "tiff"].map { .init(label: $0.uppercased(), value: $0) })]
        case "screenshots.shadow": return [.flag("Omit window shadow", capture, "disable-shadow")]
        case "screenshots.date": return [.flag("Include timestamp", capture, "include-date")]
        case "terminal.pointer-focus": return [.flag("Pointer focuses Terminal windows", "com.apple.Terminal", "FocusFollowsMouse")]
        case "music.half-stars": return [.flag("Allow half-star ratings", "com.apple.Music", "allow-half-stars")]
        case "finder.column-sizing" where ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 15:
            return [.flag("Automatically size columns", finder, "_FXEnableColumnAutoSizing")]
        case "apps.automatic-termination" where version.majorVersion == 15:
            return [.flag("Disable native automatic termination", global, "NSDisableAutomaticTermination")]
        default: return []
        }
    }

    private static func seconds(_ label: String, _ domain: String, _ key: String, _ values: [Double]) -> TweakPreferenceField {
        .init(label: label, domain: domain, key: key,
              choices: values.map { .init(label: "\($0.formatted()) seconds", value: $0) })
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

    private struct Record: Codable {
        let original: Data?
        var lastWritten: Data?
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
        guard let current = value(for: field), let data = archive(current) else { return -1 }
        return field.choices.firstIndex { archive($0.value) == data } ?? -2
    }

    func hasBackup(for fields: [TweakPreferenceField]) -> Bool {
        fields.contains { records[$0.identity] != nil }
    }

    func apply(_ fields: [TweakPreferenceField], selections: [String: Int]) throws {
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
            before.append((field, current))
            let currentData = current.flatMap(archive)
            if let previous = next[field.identity], previous.lastWritten != currentData {
                throw TweakPreferenceError.changedElsewhere(field.key)
            }
            let chosen: Any? = selection == -1 ? nil : field.choices[selection].value
            let chosenData = chosen.flatMap(archive)
            if next[field.identity] == nil {
                next[field.identity] = Record(original: currentData, lastWritten: chosenData)
            } else {
                next[field.identity]?.lastWritten = chosenData
            }
            writes.append((field, chosen))
        }
        try persist(next)
        for (field, chosen) in writes { set(chosen, for: field) }
        do {
            try synchronizeAndCheck(writes)
            records = next
        } catch {
            for (field, oldValue) in before { set(oldValue, for: field) }
            if (try? synchronizeAndCheck(before)) != nil {
                try? persist(records)
            } else {
                records = next
            }
            throw error
        }
    }

    func restore(_ fields: [TweakPreferenceField]) throws {
        var writes: [(TweakPreferenceField, Any?)] = []
        var before: [(TweakPreferenceField, Any?)] = []
        for field in fields {
            guard let record = records[field.identity] else { continue }
            let current = value(for: field)
            guard record.lastWritten == current.flatMap(archive) else {
                throw TweakPreferenceError.changedElsewhere(field.key)
            }
            before.append((field, current))
            writes.append((field, record.original.flatMap(unarchive)))
        }
        guard !writes.isEmpty else { return }
        for (field, value) in writes { set(value, for: field) }
        do {
            try synchronizeAndCheck(writes)
            var next = records
            for (field, _) in writes { next.removeValue(forKey: field.identity) }
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

    private func persist(_ records: [String: Record]) throws {
        guard let data = try? PropertyListEncoder().encode(records) else {
            throw TweakPreferenceError.writeFailed("Mac Tweaks backup")
        }
        defaults.set(data, forKey: backupKey)
        guard defaults.synchronize() else { throw TweakPreferenceError.writeFailed("Mac Tweaks backup") }
    }
}

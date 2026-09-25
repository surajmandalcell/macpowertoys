import AppKit
import SwiftUI

struct TweakDetailView: View {
    let item: TweakItem
    let backTitle: String
    let onBack: () -> Void

    @State private var selections: [String: Int] = [:]
    @State private var message: String?
    @State private var hasBackup = false
    @State private var showRestartConfirmation = false

    private var fields: [TweakPreferenceField] { TweakPreferences.fields(for: item.id) }
    private var canApply: Bool { TweakPreferences.supportsWrites(for: item.id) && fields.allSatisfy { (selections[$0.identity] ?? -2) >= -1 } }
    private var restartTarget: String? {
        if item.id.hasPrefix("dock.") { return "Dock" }
        if item.id.hasPrefix("finder.") && item.id != "finder.network-metadata" { return "Finder" }
        return nil
    }

    var body: some View {
        WorkspacePage(item.title, subtitle: item.category, actions: {
            Button(backTitle, systemImage: "chevron.left", action: onBack)
                .accessibilityIdentifier("mac-tweaks.back")
        }) {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.summary)
                    .font(.system(size: 14))

                HStack(spacing: 8) {
                    Text(item.kind.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if fields.isEmpty && item.id != "helper.keep-awake" {
                        Text(item.kind == .historical ? "Unavailable" : "Reference")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(item.kind == .historical ? .red : .secondary)
                    }
                }

                Text(item.researchCoverage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if item.id == "helper.keep-awake" {
                    if SettingsManager.shared.isToolEnabled("awake") {
                        AwakeSettingsView()
                        Text("The sleep assertion works while MacPowerToys is running. Timed sessions and the selected mode are saved by Awake.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Awake is disabled in MacPowerToys.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button("Enable Awake") { SettingsManager.shared.setToolEnabled(true, for: "awake") }
                    }
                } else if !fields.isEmpty {
                    preferenceForm
                } else {
                    Text(explanation)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let nativeDestination {
                        Button(nativeDestination.label) {
                            NSWorkspace.shared.open(nativeDestination.url)
                        }
                    }
                }

                if let referenceURL {
                    Link("Read reference", destination: referenceURL)
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
        }
        .onAppear(perform: refresh)
        .confirmationDialog("Restart \(restartTarget ?? "app") to apply changes?", isPresented: $showRestartConfirmation) {
            Button("Restart \(restartTarget ?? "app")") { restartTargetApp() }
        } message: {
            Text("Open windows may refresh. Wait for file operations to finish before restarting Finder.")
        }
    }

    private var preferenceForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(fields, id: \.identity) { field in
                HStack(spacing: 14) {
                    Text(field.label)
                        .font(.system(size: 12))
                        .frame(width: 220, alignment: .leading)
                    Picker(field.label, selection: Binding(
                        get: { selections[field.identity] ?? -2 },
                        set: { selections[field.identity] = $0 }
                    )) {
                        if selections[field.identity] == -2 {
                            Text("Existing custom value").tag(-2)
                        }
                        Text("System default").tag(-1)
                        ForEach(field.choices.indices, id: \.self) { index in
                            Text(field.choices[index].label).tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .accessibilityLabel(field.label)
                    .disabled(!TweakPreferences.supportsWrites(for: item.id))
                }
            }

            HStack(spacing: 12) {
                Button("Apply changes") { apply() }
                    .disabled(!canApply)
                    .accessibilityIdentifier("mac-tweaks.apply.\(item.id)")
                if hasBackup {
                    Button("Restore previous values") { restore() }
                        .accessibilityIdentifier("mac-tweaks.restore.\(item.id)")
                }
                if let restartTarget {
                    Button("Restart \(restartTarget)…") { showRestartConfirmation = true }
                }
            }

            Text(activationNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !TweakPreferences.supportsWrites(for: item.id) {
                Text("New changes are unavailable on this macOS release. You can still restore values saved by Mac Tweaks.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let nativeDestination {
                Button(nativeDestination.label) { NSWorkspace.shared.open(nativeDestination.url) }
            }
            Text("The preference mapping is documented. Its visible effect still needs checking on each supported macOS release.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var activationNote: String {
        if item.id == "finder.network-metadata" { return "Apple specifies signing out and back in after changing this setting." }
        if item.id == "terminal.pointer-focus" { return "Quit and reopen Terminal when your shell sessions are finished. Mac Tweaks will not close it." }
        if item.id == "apps.automatic-termination" { return "This affects native automatic termination only. It does not stop App Nap, memory pressure, or manual quitting." }
        if item.id.hasPrefix("screenshots.") { return "Take a new screenshot to check the effect. Existing captures are unchanged." }
        if item.id == "menubar.spacing" { return "Sign out and back in, or reopen affected status apps, to check spacing and click targets." }
        if restartTarget != nil { return "Restart the target app when ready to check the visible effect." }
        return "Some apps read preferences only when they start. Reopen affected apps to check the effect."
    }

    private var explanation: String {
        switch item.kind {
        case .native:
            if item.id.hasPrefix("native.finder-") { return "Finder already provides this choice. Open Finder, then use Finder > Settings or the View menu and search for the title above." }
            if item.id.hasPrefix("native.screenshot-") { return "Screenshot already provides this choice in Options. Open Screenshot and choose the setting there." }
            if item.id == "native.app-options" { return "Each named Apple app owns its own Settings. Open that app and choose its Settings menu." }
            return "Apple already provides this setting. Open System Settings and search for the title above. Mac Tweaks does not duplicate its control."
        case .helper:
            return "This behavior needs code running in the background, with feature-specific permissions and recovery. The supplied catalogue does not establish a working implementation for this app."
        case .advanced:
            return item.id == "hardware.auto-start"
                ? "Apple documents BootPreference for Apple silicon laptops. Administrator authorization and exact NVRAM rollback need a dedicated control."
                : "Apple documents pmset schedules. A safe editor must preserve unrelated events and account for FileVault, unsaved work, and administrator authorization."
        case .candidate:
            return "A key or another product suggests this may be possible, but its behavior has not been checked on all target macOS versions."
        case .historical:
            return "This old recipe is excluded from supported controls because it is obsolete, unreliable, or has known side effects."
        case .versioned:
            if item.id == "finder.column-sizing" {
                return "The hidden preference applies on Sequoia and Tahoe 26.0. Finder exposes this choice in its native View Options from Tahoe 26.1 onward."
            }
            if item.id.hasPrefix("launchpad.") { return "This is a legacy Launchpad feature for macOS 15. Its old mechanism does not apply to the newer launcher." }
            if ["appearance.corners", "appearance.sidebars"].contains(item.id) { return "Documented from Tahoe 26.4 and on Golden Gate, but the exact key still needs independent verification." }
            return "Availability changes by macOS minor release or app version. The exact mechanism and visible effect need verification before a control is enabled."
        case .preference:
            return "The feature is documented, but its exact preference key or safe value range has not been established here."
        }
    }

    private var nativeDestination: (label: String, url: URL)? {
        if item.id == "finder.column-sizing",
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            return ("Open Finder", URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }
        guard item.kind == .native else { return nil }
        if item.id.hasPrefix("native.finder-") {
            return ("Open Finder", URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }
        if item.id.hasPrefix("native.screenshot-") {
            return ("Open Screenshot", URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
        }
        if item.id == "native.app-options" { return nil }
        return ("Open System Settings", URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private var referenceURL: URL? {
        let url: String?
        switch item.id {
        case "finder.network-metadata": url = "https://support.apple.com/en-us/102064"
        case "hardware.auto-start": url = "https://support.apple.com/en-us/120622"
        case "power.schedule": url = "https://support.apple.com/guide/mac-help/schedule-your-mac-to-turn-on-or-off-mchl40376151/mac"
        case "input.hid-remap": url = "https://developer.apple.com/library/archive/technotes/tn2450/_index.html"
        case "security.sudo-touchid": url = "https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/security/pam.nix"
        case "helper.keep-awake": url = nil
        case "native.screenshot-location", "native.screenshot-thumbnail", "native.screenshot-memory":
            url = "https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac"
        case "native.tiling": url = "https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac"
        case _ where item.id.hasPrefix("native.finder-"): url = nil
        case _ where item.kind == .native: url = "https://support.apple.com/guide/mac-help/change-system-settings-mh15217/mac"
        case _ where item.id.hasPrefix("dock."): url = "https://www.bresink.com/osx/0TinkerTool/details.html"
        case "helper.mouse-scroll", "helper.pointer-profiles", "helper.mouse-buttons": url = "https://linearmouse.app/en/"
        case _ where item.id.hasPrefix("helper."): url = "https://sindresorhus.com/supercharge"
        case _ where item.kind == .historical: url = "https://www.bresink.com/osx/0TinkerTool/issues.html"
        case _ where item.kind == .preference || item.kind == .versioned:
            url = "https://www.bresink.com/osx/0TinkerTool/details.html"
        default: url = nil
        }
        return url.flatMap(URL.init(string:))
    }

    private func refresh() {
        selections = Dictionary(uniqueKeysWithValues: fields.map { ($0.identity, TweakPreferenceStore.shared.selectedChoice(for: $0)) })
        hasBackup = TweakPreferenceStore.shared.hasBackup(for: fields)
    }

    private func apply() {
        guard canApply else { return }
        do {
            try TweakPreferenceStore.shared.apply(fields, selections: selections)
            message = "Saved. Check the visible effect after the indicated restart or sign-in."
            refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() {
        do {
            try TweakPreferenceStore.shared.restore(fields)
            message = "Previous values restored. Follow the same restart guidance to check the result."
            refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    private func restartTargetApp() {
        guard let restartTarget else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [restartTarget]
        do {
            try process.run()
            process.waitUntilExit()
            message = process.terminationStatus == 0 ? "\(restartTarget) is restarting." : "\(restartTarget) was not running."
        } catch {
            message = "Could not restart \(restartTarget): \(error.localizedDescription)"
        }
    }
}

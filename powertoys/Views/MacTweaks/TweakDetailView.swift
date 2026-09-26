import SwiftUI

struct TweakDetailView: View {
    let item: TweakItem
    let onRestore: () -> Void

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
        VStack(alignment: .leading, spacing: 14) {
            Text(item.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if item.id == "helper.keep-awake" {
                if SettingsManager.shared.isToolEnabled("awake") {
                    AwakeSettingsView()
                } else {
                    Button("Enable Awake") { SettingsManager.shared.setToolEnabled(true, for: "awake") }
                }
            } else {
                preferenceForm
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
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
            onRestore()
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

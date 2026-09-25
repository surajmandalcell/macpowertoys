import AVFoundation
import Combine
import ServiceManagement
import SwiftUI

struct MacTweaksWindowView: View {
    @State private var search = ""
    @State private var selectedID = "mic-lock"
    @State private var micLock = MicLockService.shared
    @State private var meter = MicInputLevelMonitor()
    @State private var showReviveConfirmation = false
    @State private var reviveMessage: String?
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    private var matches: [TweakItem] { TweakSearch.results(for: search) }

    private var selectedItem: TweakItem? {
        matches.first(where: { $0.id == selectedID }) ?? (search.isEmpty ? TweakSearch.micLock : matches.first)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.compactSidebarWidth)
            Group {
                if selectedItem?.id == "mic-lock" { micLockPage }
                else if let selectedItem {
                    TweakDetailView(item: selectedItem)
                        .id(selectedItem.id)
                } else {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "mac-tweaks"))
        .onAppear {
            micLock.setWindowOpen(true)
            meter.refreshPermission()
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onDisappear {
            meter.stop()
            micLock.setWindowOpen(false)
        }
        .onChange(of: micLock.currentUID) { _, _ in
            meter.stop()
            if meter.permission == .authorized { meter.start() }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            micLock.refreshControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            meter.refreshPermission()
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
        .confirmationDialog("Restart Mac audio?", isPresented: $showReviveConfirmation) {
            Button("Revive Audio") { reviveAudio() }
        } message: {
            Text("Audio in other apps may stop briefly. macOS may ask for administrator approval.")
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar)
            SidebarTitle(text: "Mac Tweaks")
            VStack(spacing: 4) {
                SidebarSearchField(text: $search, placeholder: "Search tweaks")
                    .accessibilityLabel("Search tweaks")
                    .padding(.bottom, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ForEach(TweakCatalog.categories, id: \.self) { category in
                                let items = matches.filter { $0.category == category }
                                if !items.isEmpty {
                                    Text(category.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.top, 12)
                                        .padding(.bottom, 3)
                                    ForEach(items) { item in sidebarItem(item) }
                                }
                            }
                        } else {
                            ForEach(matches) { item in sidebarItem(item) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .thinScrollIndicators()
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)
            .padding(.bottom, 12)
        }
    }

    private func sidebarItem(_ item: TweakItem) -> some View {
        SidebarRow(icon: item.id == "mic-lock" ? "mic" : icon(for: item.category),
                   title: item.title, isSelected: selectedItem?.id == item.id) {
            selectedID = item.id
        }
        .accessibilityIdentifier("mac-tweaks.item.\(item.id)")
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Dock": "dock.rectangle"
        case "Finder": "folder"
        case "Input": "keyboard"
        case "Screenshots": "camera.viewfinder"
        case "Appearance": "paintbrush"
        case "Power and hardware": "power"
        case "Menu bar": "menubar.rectangle"
        case "Built-in apps": "app"
        case "Historical": "archivebox"
        default: "slider.horizontal.3"
        }
    }

    private var micLockPage: some View {
        WorkspacePage("Mic Lock", subtitle: "Keep Bluetooth headsets on high-quality output", actions: {
            Button("Refresh Devices", systemImage: "arrow.clockwise") { micLock.refresh() }
                .accessibilityIdentifier("mac-tweaks.refresh")
        }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keep a preferred microphone selected")
                            .font(.system(size: 15, weight: .medium))
                        Text("Mac Tweaks restores the first available saved input when macOS switches to a headset microphone.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Mic Lock", isOn: Binding(
                        get: { micLock.isEnabled },
                        set: { micLock.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Enable Mic Lock")
                    .accessibilityIdentifier("mac-tweaks.mic-lock.enabled")
                }

                currentInputSection
                savedInputSection

                Toggle("Open MacPowerToys at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { setOpenAtLogin($0) }
                ))
                .font(.system(size: 12))
                .help("Mic Lock can work after login only while MacPowerToys is running.")
                if let loginMessage {
                    HStack {
                        Text(loginMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }

                HStack {
                    Button("Revive Audio…") { showReviveConfirmation = true }
                    Text("Use if USB or dock audio stays missing after Refresh Devices.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let message = micLock.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let reviveMessage {
                    Text(reviveMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var currentInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current input").font(.system(size: 13, weight: .medium))
            Text(micLock.devices.first(where: { $0.id == micLock.currentUID })?.name ?? "No input available")
                .font(.system(size: 13))
            HStack(spacing: 16) {
                if let muted = micLock.muted {
                    Toggle("Muted", isOn: Binding(
                        get: { micLock.muted ?? muted },
                        set: { micLock.setMuted($0) }
                    ))
                    .accessibilityIdentifier("mac-tweaks.mic-lock.muted")
                } else { Text("Mute unavailable").foregroundStyle(.secondary) }
                if let volume = micLock.volume {
                    Slider(value: Binding(
                        get: { Double(micLock.volume ?? volume) },
                        set: { micLock.setVolume(Float($0)) }
                    ), in: 0...1) { Text("Input volume") }
                    .frame(maxWidth: 260)
                } else { Text("Input volume unavailable").foregroundStyle(.secondary) }
            }
            .font(.system(size: 12))

            if meter.permission == .authorized {
                HStack(spacing: 10) {
                    Text("Input level").font(.system(size: 12))
                    ProgressView(value: Double(meter.level), total: 1)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Input level")
                }
            } else if meter.permission == .notDetermined {
                Button("Enable Input Level") { Task { await meter.requestAndStart() } }
                    .help("Allow microphone access to show a live level meter. Audio is never saved.")
            } else {
                Button("Open Microphone Settings") { meter.openMicrophoneSettings() }
            }
            if let error = meter.error { Text(error).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }

    private var savedInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Input selection").font(.system(size: 13, weight: .medium))
            Text("Mic Lock tries these in order, then a built-in or other non-wireless microphone.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 12) {
                    Text(index == 0 ? "Primary" : "Fallback \(index)")
                        .font(.system(size: 12))
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { micLock.savedInputs[index]?.uid ?? "" },
                        set: { micLock.setSavedInput($0.isEmpty ? nil : $0, at: index) }
                    )) {
                        Text("None").tag("")
                        if let saved = micLock.savedInputs[index],
                           !micLock.devices.contains(where: { $0.id == saved.uid }) {
                            Text("\(saved.name) (Unavailable)").tag(saved.uid)
                        }
                        ForEach(micLock.devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 340)
                    .accessibilityLabel(index == 0 ? "Primary microphone" : "Fallback \(index) microphone")
                }
            }
        }
    }

    private func reviveAudio() {
        reviveMessage = "Restarting audio…"
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"]
            let pipe = Pipe()
            process.standardError = pipe
            let result: String
            do {
                try process.run()
                let detail = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                process.waitUntilExit()
                result = process.terminationStatus == 0 ? "Audio restarted. Refreshing devices…" :
                    "Could not restart audio. \(detail.isEmpty ? "Administrator approval may be required." : detail)"
            } catch {
                result = "Could not restart audio: \(error.localizedDescription)"
            }
            await MainActor.run {
                reviveMessage = result
                micLock.refresh()
            }
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            opensAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Allow MacPowerToys in Login Items to finish setup." : nil
        } catch {
            opensAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = "Could not change Login Items: \(error.localizedDescription)"
        }
    }
}

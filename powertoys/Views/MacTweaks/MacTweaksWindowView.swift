import AVFoundation
import Combine
import ServiceManagement
import SwiftUI

struct MacTweaksWindowView: View {
    @State private var search = ""
    @State private var selectedCategory = "Input"
    @State private var selectedID: String?
    @State private var micLock = MicLockService.shared
    @State private var meter = MicInputLevelMonitor()
    @State private var showReviveConfirmation = false
    @State private var reviveMessage: String?
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var allItems: [TweakItem] { [TweakSearch.micLock] + TweakCatalog.items }
    private var visibleItems: [TweakItem] {
        isSearching ? TweakSearch.results(for: search) : allItems.filter { $0.category == selectedCategory }
    }

    private var selectedItem: TweakItem? {
        allItems.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.compactSidebarWidth)
            Group {
                if selectedItem?.id == "mic-lock" { micLockPage }
                else if let selectedItem {
                    TweakDetailView(item: selectedItem, backTitle: backTitle) { selectedID = nil }
                        .id(selectedItem.id)
                } else {
                    categoryPage
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
        .onChange(of: search) { _, _ in selectedID = nil }
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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(TweakCatalog.sidebarGroups.indices, id: \.self) { groupIndex in
                            let group = TweakCatalog.sidebarGroups[groupIndex]
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 4)
                                ForEach(group.categories, id: \.self) { category in
                                    SidebarRow(icon: icon(for: category), title: shortTitle(for: category),
                                               isSelected: !isSearching && selectedCategory == category) {
                                        selectedCategory = category
                                        selectedID = nil
                                        search = ""
                                    }
                                    .accessibilityIdentifier("mac-tweaks.category.\(category)")
                                    .accessibilityLabel(category)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
                }
                .thinScrollIndicators()
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)
            .padding(.bottom, 12)
        }
    }

    private var backTitle: String {
        isSearching ? "Results" : shortTitle(for: selectedCategory)
    }

    private var categoryPage: some View {
        WorkspacePage(isSearching ? "Search results" : selectedCategory,
                      subtitle: "\(visibleItems.count) \(visibleItems.count == 1 ? "setting" : "settings")") {
            if visibleItems.isEmpty {
                ContentUnavailableView.search(text: search)
                Button("Clear search") { search = "" }
            } else if isSearching {
                VStack(spacing: 8) {
                    ForEach(visibleItems) { item in settingCard(item) }
                }
                .frame(maxWidth: 760, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(["Controls", "Apple settings", "Research", "Historical"], id: \.self) { section in
                        let items = visibleItems.filter { sectionName(for: $0) == section }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(items) { item in settingCard(item) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    private func settingCard(_ item: TweakItem) -> some View {
        Button {
            selectedID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(isSearching ? item.category : sectionName(for: item))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(item.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 10))
        .accessibilityIdentifier("mac-tweaks.card.\(item.id)")
        .accessibilityLabel("\(item.title), \(item.category), \(sectionName(for: item)). \(item.summary)")
    }

    private func sectionName(for item: TweakItem) -> String {
        if item.id == "mic-lock" || item.id == "helper.keep-awake" || TweakPreferences.supportsWrites(for: item.id) {
            return "Controls"
        }
        if item.kind == .native || item.id == "finder.column-sizing" && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            return "Apple settings"
        }
        return item.kind == .historical ? "Historical" : "Research"
    }

    private func shortTitle(for category: String) -> String {
        switch category {
        case "Windows and dialogs": "Windows"
        case "Built-in apps": "Apps"
        case "Power and hardware": "Power"
        case "Regional formats": "Formats"
        case "Developer controls": "Developer"
        default: category
        }
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Dock": "dock.rectangle"
        case "Finder": "folder"
        case "Input": "keyboard"
        case "Screenshots": "camera.viewfinder"
        case "Appearance": "paintbrush"
        case "Power and hardware": "bolt"
        case "Menu bar": "menubar.rectangle"
        case "Built-in apps": "square.grid.2x2"
        case "Windows and dialogs": "macwindow"
        case "Regional formats": "globe"
        case "Diagnostics": "waveform.path.ecg"
        case "Launchpad": "square.grid.3x3"
        case "Continuity": "link"
        case "Developer controls": "chevron.left.forwardslash.chevron.right"
        case "Enhancements": "slider.horizontal.3"
        case "Historical": "archivebox"
        default: "slider.horizontal.3"
        }
    }

    private var micLockPage: some View {
        WorkspacePage("Mic Lock", subtitle: "Keep Bluetooth headsets on high-quality output", actions: {
            Button(backTitle, systemImage: "chevron.left") { selectedID = nil }
                .accessibilityIdentifier("mac-tweaks.back")
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

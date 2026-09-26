import AVFoundation
import Combine
import ServiceManagement
import SwiftUI

struct MacTweaksWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var selectedCategory = "Input"
    @State private var expandedID: String?
    @State private var micLock = MicLockService.shared
    @State private var meter = MicInputLevelMonitor()
    @State private var showReviveConfirmation = false
    @State private var reviveMessage: String?
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var allItems: [TweakItem] {
        [TweakSearch.micLock] + TweakCatalog.items.filter { item in
            item.id == "helper.keep-awake" || TweakPreferences.supportsWrites(for: item.id) ||
                TweakPreferenceStore.shared.hasBackup(for: TweakPreferences.fields(for: item.id))
        }
    }
    private var visibleItems: [TweakItem] {
        isSearching ? TweakSearch.results(for: search, in: allItems) : allItems.filter { $0.category == selectedCategory }
    }
    private var visibleSidebarGroups: [(title: String, categories: [String])] {
        let categories = Set(allItems.map(\.category))
        return TweakCatalog.sidebarGroups.compactMap { group in
            let visible = group.categories.filter { categories.contains($0) }
            return visible.isEmpty ? nil : (group.title, visible)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.compactSidebarWidth)
            categoryPage
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "mac-tweaks"))
        .onAppear {
            micLock.setWindowOpen(false)
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onDisappear {
            meter.stop()
            micLock.setWindowOpen(false)
        }
        .onChange(of: micLock.currentUID) { _, _ in
            meter.stop()
            if expandedID == "mic-lock" && meter.permission == .authorized { meter.start() }
        }
        .onChange(of: expandedID) { _, id in
            micLock.setWindowOpen(id == "mic-lock")
            meter.stop()
            if id == "mic-lock" {
                meter.refreshPermission()
                if meter.permission == .authorized { meter.start() }
            }
        }
        .onChange(of: search) { _, _ in expandedID = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if expandedID == "mic-lock" { meter.refreshPermission() }
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
                        ForEach(visibleSidebarGroups.indices, id: \.self) { groupIndex in
                            let group = visibleSidebarGroups[groupIndex]
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
                                        expandedID = nil
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

    private var categoryPage: some View {
        WorkspacePage(isSearching ? "Search results" : selectedCategory,
                      subtitle: "\(visibleItems.count) \(visibleItems.count == 1 ? "setting" : "settings")") {
            if visibleItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("No matches for “\(trimmedSearch)”")
                        .font(.system(size: 14, weight: .medium))
                    Text("Try another setting name or related word.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Clear search") { search = "" }
                        .controlSize(.small)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else if let first = visibleItems.first {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(spacing: 6) {
                            if expandedID == first.id { settingCardDetail(first) }
                            ForEach(visibleItems.dropFirst()) { item in settingCard(item) }
                        }
                        .padding(.top, expandedID == first.id ? 0 : 6)
                    } header: {
                        settingCardHeader(first)
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    private func settingCard(_ item: TweakItem) -> some View {
        VStack(spacing: 0) {
            settingCardHeader(item)
            if expandedID == item.id { settingCardDetail(item) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingCardHeader(_ item: TweakItem) -> some View {
        let isExpanded = expandedID == item.id
        return Button {
            withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) {
                expandedID = isExpanded ? nil : item.id
            }
        } label: {
            HStack(spacing: 12) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSearching {
                    Text(item.category)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 12))
        .accessibilityIdentifier("mac-tweaks.card.\(item.id)")
        .accessibilityLabel(item.title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .background(Color.primary.opacity(0.03),
                    in: UnevenRoundedRectangle(topLeadingRadius: 12,
                                               bottomLeadingRadius: isExpanded ? 0 : 12,
                                               bottomTrailingRadius: isExpanded ? 0 : 12,
                                               topTrailingRadius: 12))
    }

    private func settingCardDetail(_ item: TweakItem) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 14)
            Group {
                if item.id == "mic-lock" { micLockControls }
                else {
                    TweakDetailView(item: item) {
                        if !TweakPreferences.supportsWrites(for: item.id) { expandedID = nil }
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03),
                    in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
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

    private var micLockControls: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            TweakExampleView(item: TweakSearch.micLock)
            currentInputSection
            savedInputSection
            Button("Refresh Devices", systemImage: "arrow.clockwise") { micLock.refresh() }
                .accessibilityIdentifier("mac-tweaks.refresh")

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
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            micLock.refreshControls()
        }
    }

    private var currentInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current input").font(.system(size: 13, weight: .medium))
            Text(micLock.devices.first(where: { $0.id == micLock.currentUID })?.name ?? "No input available")
                .font(.system(size: 13))
            HStack(spacing: 18) {
                if let muted = micLock.muted {
                    Toggle("Muted", isOn: Binding(
                        get: { micLock.muted ?? muted },
                        set: { micLock.setMuted($0) }
                    ))
                    .accessibilityIdentifier("mac-tweaks.mic-lock.muted")
                } else { Text("Mute unavailable").foregroundStyle(.secondary) }
                if let volume = micLock.volume {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input volume")
                        Slider(value: Binding(
                            get: { Double(micLock.volume ?? volume) },
                            set: { micLock.setVolume(Float($0)) }
                        ), in: 0...1) { Text("Input volume") }
                        .labelsHidden()
                        .accessibilityLabel("Input volume")
                    }
                    .frame(maxWidth: 240)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Input selection").font(.system(size: 13, weight: .medium))
            Text("Mic Lock tries these in order, then a built-in or other non-wireless microphone.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 12) {
                    Text(index == 0 ? "Primary" : "Fallback \(index)")
                        .font(.system(size: 12))
                        .frame(width: 80, alignment: .leading)
                    Spacer(minLength: 8)
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
                    .frame(width: 320)
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

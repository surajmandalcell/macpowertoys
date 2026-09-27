import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI

enum MacTweaksLayout {
    static let windowSize = NSSize(width: 900, height: 620)
    static let contentSize = NSSize(
        width: windowSize.width,
        height: windowSize.height - UtilityLayout.hiddenTitlebarBottomSurplus
    )
    static let sidebarWidth: CGFloat = 200
    static let titlebarHeight: CGFloat = 64
    static let contentInset: CGFloat = 28
    static let panelGap: CGFloat = 16
    static let trafficLightVerticalOffset: CGFloat = 16
}

private struct MacTweaksCategory: Identifiable {
    let id: String
    let title: String
    let group: String
    let glyph: MacTweaksGlyphName
    let itemIDs: [String]
    let preview: MacTweaksPreviewKind

    static let all: [Self] = [
        .init(id: "input", title: "Input", group: "Everyday", glyph: .input,
              itemIDs: ["mic-lock", "input.press-hold"], preview: .apps),
        .init(id: "dock", title: "Dock", group: "Everyday", glyph: .dock,
              itemIDs: ["dock.reveal-delay", "dock.animation-duration", "dock.hidden-app-dimming", "dock.lock-size", "dock.lock-contents", "dock.stack-selection", "dock.minimize-effect", "dock.slow-motion", "dock.switcher-displays"], preview: .dockReveal),
        .init(id: "finder", title: "Finder", group: "Everyday", glyph: .finder,
              itemIDs: ["finder.hidden-files", "finder.quit", "finder.path-title", "finder.sounds", "finder.network-metadata", "finder.column-sizing"], preview: .finder),
        .init(id: "windows", title: "Windows", group: "Everyday", glyph: .windows,
              itemIDs: ["dialogs.expanded-save", "windows.scroll-animation"], preview: .windows),
        .init(id: "screenshots", title: "Screenshots", group: "Everyday", glyph: .screenshots,
              itemIDs: ["screenshots.format", "screenshots.shadow", "screenshots.date"], preview: .screenshots),
        .init(id: "apps", title: "Apps", group: "Everyday", glyph: .apps,
              itemIDs: ["terminal.pointer-focus", "music.half-stars", "apps.automatic-termination"], preview: .apps),
        .init(id: "power", title: "Power", group: "System", glyph: .power,
              itemIDs: ["helper.keep-awake"], preview: .power),
        .init(id: "menubar", title: "Menu bar", group: "System", glyph: .menubar,
              itemIDs: ["menubar.spacing"], preview: .menubar)
    ]
}

private struct MacTweaksModifiedEntry: Identifiable {
    let category: MacTweaksCategory
    let item: TweakItem
    let field: TweakPreferenceField
    var id: String { field.identity }
}

struct MacTweaksWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    @State private var search = ""
    @State private var selectedPage = "dock"
    @State private var preferenceRevision = 0
    @State private var notice: MacTweaksNotice?
    @State private var noticeTask: Task<Void, Never>?
    @State private var restartRequest: (name: String, bundleID: String)?
    @State private var showsResetAllConfirmation = false
    @State private var showsReviveConfirmation = false
    @State private var micLock = MicLockService.shared
    @State private var meter = MicInputLevelMonitor()
    @State private var awake = AwakeService.shared
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var refreshRotation = 0.0

    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedSearch.isEmpty }
    private var selectedCategory: MacTweaksCategory {
        MacTweaksCategory.all.first { $0.id == selectedPage } ?? MacTweaksCategory.all[1]
    }
    private var pageTitle: String {
        if isSearching { return "Search" }
        if selectedPage == "modified" { return "Modified" }
        if selectedPage == "about" { return "About" }
        return selectedCategory.title
    }
    private var allWorkingItems: [TweakItem] {
        MacTweaksCategory.all.flatMap { category in
            category.itemIDs.compactMap { id in
                let item = item(for: id)
                return shouldShow(item) ? item : nil
            }
        }
    }
    private var modifiedEntries: [MacTweaksModifiedEntry] {
        _ = preferenceRevision
        return MacTweaksCategory.all.flatMap { category in
            category.itemIDs.flatMap { id -> [MacTweaksModifiedEntry] in
                let item = item(for: id)
                return TweakPreferences.fields(for: id).compactMap { field in
                    TweakPreferenceStore.shared.isModified(field)
                        ? .init(category: category, item: item, field: field) : nil
                }
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                sidebar
                workspace
            }
            if let notice {
                noticeView(notice)
                    .padding(.trailing, 24)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .frame(width: MacTweaksLayout.contentSize.width, height: MacTweaksLayout.contentSize.height)
        .background(MacTweaksPalette.window)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "mac-tweaks"))
        .environment(\.colorScheme, .dark)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onAppear {
            micLock.setWindowOpen(true)
            opensAtLogin = SMAppService.mainApp.status == .enabled
            syncInputMonitoring()
        }
        .onDisappear {
            noticeTask?.cancel()
            meter.stop()
            micLock.setWindowOpen(false)
        }
        .onChange(of: selectedPage) { _, _ in syncInputMonitoring() }
        .onChange(of: micLock.currentUID) { _, _ in syncInputMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            opensAtLogin = SMAppService.mainApp.status == .enabled
            if selectedPage == "input" { meter.refreshPermission() }
        }
        .task(id: selectedPage) {
            guard selectedPage == "input", !isSearching else { return }
            while !Task.isCancelled {
                micLock.refreshControls()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
        .onExitCommand {
            if !search.isEmpty { search = "" } else { searchFocused = false }
        }
        .confirmationDialog(
            "Restart \(restartRequest?.name ?? "app") now?",
            isPresented: Binding(get: { restartRequest != nil }, set: { if !$0 { restartRequest = nil } })
        ) {
            Button("Restart \(restartRequest?.name ?? "app")") { restartRequestedApp() }
            Button("Later", role: .cancel) { restartRequest = nil }
        } message: {
            Text("The setting is already saved. Restart later if you are in the middle of work.")
        }
        .confirmationDialog("Reset every modified setting?", isPresented: $showsResetAllConfirmation) {
            Button("Reset all", role: .destructive) { resetAllModified() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mac Tweaks restores only values it changed. Unrelated settings stay untouched.")
        }
        .confirmationDialog("Restart Mac audio?", isPresented: $showsReviveConfirmation) {
            Button("Revive Audio") { reviveAudio() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Audio in other apps may stop briefly. macOS will request administrator approval.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { navigate(to: "about") } label: {
                    Text("Mac Tweaks")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(white: 0.894))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("About Mac Tweaks")
                .accessibilityIdentifier("mac-tweaks.about")
                Spacer()
            }
            .padding(.leading, 84)
            .frame(height: MacTweaksLayout.titlebarHeight)

            MacTweaksSearchField(text: $search, isFocused: $searchFocused)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarGroup("Everyday")
                    sidebarGroup("System").padding(.top, 24)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollIndicators()

            VStack(spacing: 2) {
                MacTweaksBottomSidebarButton(
                    title: "Modified", symbol: "arrow.counterclockwise",
                    selected: !isSearching && selectedPage == "modified",
                    enabled: !modifiedEntries.isEmpty
                ) { navigate(to: "modified") }
                MacTweaksBottomSidebarButton(
                    title: "About", symbol: "info.circle",
                    selected: !isSearching && selectedPage == "about", enabled: true
                ) { navigate(to: "about") }
            }
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(MacTweaksPalette.line).frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
            }
        }
        .frame(width: MacTweaksLayout.sidebarWidth)
        .background(MacTweaksPalette.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(MacTweaksPalette.line).frame(width: 1) }
    }

    private func sidebarGroup(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased())
                .font(.system(size: 9.5, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color(white: 0.505))
                .padding(.leading, 10)
                .padding(.bottom, 6)
            ForEach(MacTweaksCategory.all.filter { $0.group == name }) { category in
                MacTweaksSidebarButton(category: category, selected: !isSearching && selectedPage == category.id) {
                    navigate(to: category.id)
                }
                .accessibilityIdentifier("mac-tweaks.category.\(category.title)")
            }
        }
    }

    private var workspace: some View {
        ZStack(alignment: .topTrailing) {
            MacTweaksPalette.window
            MacTweaksDither(strength: 0.09)
                .frame(width: 470, height: 120)
            VStack(spacing: 0) {
                HStack {
                    Text(pageTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(MacTweaksPalette.text)
                    Spacer()
                    if !isSearching && selectedPage == "modified" {
                        MacTweaksBorderedButton("Reset all", symbol: "arrow.counterclockwise") {
                            showsResetAllConfirmation = true
                        }
                        .disabled(modifiedEntries.isEmpty)
                    }
                }
                .padding(.horizontal, MacTweaksLayout.contentInset)
                .frame(height: MacTweaksLayout.titlebarHeight)

                ScrollView {
                    Group {
                        if isSearching { searchPage }
                        else if selectedPage == "modified" { modifiedPage }
                        else if selectedPage == "about" { aboutPage }
                        else { categoryPage }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, MacTweaksLayout.contentInset)
                    .padding(.bottom, MacTweaksLayout.contentInset)
                }
                .thinScrollIndicators()
            }
        }
    }

    @ViewBuilder
    private var categoryPage: some View {
        switch selectedPage {
        case "input": inputPage
        case "dock": dockPage
        case "power": powerPage
        default: genericPage(selectedCategory)
        }
    }

    private var dockPage: some View {
        VStack(spacing: MacTweaksLayout.panelGap) {
            HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
                preferencePreviewPanel("Motion", glyph: .motion,
                                       itemIDs: ["dock.reveal-delay", "dock.animation-duration"],
                                       preview: .dockReveal)
                preferencePreviewPanel("Window animation", glyph: .animation,
                                       itemIDs: ["dock.minimize-effect", "dock.slow-motion"],
                                       preview: .minimize)
            }
            .frame(height: 292)
            HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
                preferencePanel("Layout & appearance", glyph: .layers,
                                itemIDs: ["dock.lock-size", "dock.lock-contents", "dock.hidden-app-dimming", "dock.stack-selection", "dock.switcher-displays"])
                MacTweaksPanel("Stack & app switcher", glyph: .dock) {
                    MacTweaksPreviewView(kind: .layout)
                }
            }
            .frame(height: 260)
        }
    }

    private var inputPage: some View {
        VStack(spacing: MacTweaksLayout.panelGap) {
            MacTweaksStandalonePanel {
                MacTweaksInlineRow("Mic Lock") {
                    Toggle("Mic Lock", isOn: Binding(get: { micLock.isEnabled }, set: micLock.setEnabled))
                        .labelsHidden().toggleStyle(MacTweaksToggleStyle())
                        .accessibilityLabel("Mic Lock")
                        .accessibilityIdentifier("mac-tweaks.mic-lock.enabled")
                }
            }
            HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
                MacTweaksPanel("Input priority", glyph: .input) {
                    ForEach(0..<4, id: \.self) { index in
                        MacTweaksInlineRow(index == 0 ? "Primary" : "Fallback \(index)") {
                            microphoneMenu(index: index)
                        }
                        if index < 3 { MacTweaksRowDivider() }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { refreshMicrophones() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .rotationEffect(.degrees(refreshRotation))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(MacTweaksHoverButtonStyle(cornerRadius: 5))
                    .foregroundStyle(MacTweaksPalette.secondary)
                    .disabled(!micLock.isEnabled)
                    .help("Refresh devices")
                    .accessibilityLabel("Refresh devices")
                    .accessibilityIdentifier("mac-tweaks.mic-lock.refresh")
                    .padding(.top, 7)
                    .padding(.trailing, 10)
                }
                MacTweaksPanel("Current input", glyph: .input) {
                    MacTweaksInlineRow("Microphone") {
                        Text(currentMicrophoneName).lineLimit(1)
                            .font(.system(size: 11)).foregroundStyle(MacTweaksPalette.secondary)
                    }
                    if micLock.volume != nil {
                        MacTweaksRowDivider()
                        MacTweaksInlineRow("Input volume") { inputVolumeControl }
                    }
                    if micLock.muted != nil {
                        MacTweaksRowDivider()
                        MacTweaksInlineRow("Mute microphone") {
                            Toggle("Mute microphone", isOn: Binding(get: { micLock.muted ?? false }, set: micLock.setMuted))
                                .labelsHidden().toggleStyle(MacTweaksToggleStyle())
                                .accessibilityLabel("Mute microphone")
                        }
                    }
                    MacTweaksRowDivider()
                    MacTweaksInlineRow("Input level") { inputLevelControl }
                }
            }
            .frame(height: 216)
            HStack(spacing: MacTweaksLayout.panelGap) {
                MacTweaksStandalonePanel {
                    MacTweaksInlineRow("Open at login") {
                        Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpenAtLogin))
                            .labelsHidden().toggleStyle(MacTweaksToggleStyle())
                            .accessibilityLabel("Open at login")
                    }
                }
                MacTweaksStandalonePanel {
                    MacTweaksInlineRow("Audio service") {
                        MacTweaksBorderedButton("Revive Audio", symbol: "lock") { showsReviveConfirmation = true }
                    }
                }
            }
            preferencePanel("Keyboard", glyph: .input, itemIDs: ["input.press-hold"])
        }
    }

    private var powerPage: some View {
        HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
            MacTweaksPanel("Power preferences", glyph: .power) {
                MacTweaksInlineRow("Keep this Mac awake") {
                    Toggle("Keep this Mac awake", isOn: Binding(
                        get: { awake.configuration.mode != .passive },
                        set: { enabled in
                            SettingsManager.shared.setToolEnabled(true, for: "awake")
                            awake.setMode(enabled ? .indefinite : .passive)
                        }
                    )).labelsHidden().toggleStyle(MacTweaksToggleStyle())
                        .accessibilityLabel("Keep this Mac awake")
                }
                MacTweaksRowDivider()
                MacTweaksInlineRow("Duration") { awakeDurationMenu }
                MacTweaksRowDivider()
                MacTweaksInlineRow("Keep display on") {
                    Toggle("Keep display on", isOn: Binding(get: { awake.configuration.keepDisplayOn }, set: awake.setKeepDisplayOn))
                        .labelsHidden().toggleStyle(MacTweaksToggleStyle())
                        .accessibilityLabel("Keep display on")
                }
                MacTweaksRowDivider()
                MacTweaksInlineRow("Status") {
                    Text(awake.statusText).font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(awake.assertionError == nil ? MacTweaksPalette.secondary : MacTweaksPalette.accent)
                        .lineLimit(1)
                }
            }
            MacTweaksPanel("Power preview", glyph: .power) {
                MacTweaksPreviewView(kind: .power)
            }
            .frame(height: 260)
        }
    }

    private func genericPage(_ category: MacTweaksCategory) -> some View {
        HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
            preferencePanel(groupTitle(for: category), glyph: category.glyph, itemIDs: category.itemIDs)
            MacTweaksPanel(previewTitle(for: category), glyph: category.glyph) {
                MacTweaksPreviewView(kind: category.preview)
            }
            .frame(height: 280)
        }
    }

    private var searchPage: some View {
        let results = TweakSearch.results(for: trimmedSearch, in: allWorkingItems)
        return Group {
            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light)).foregroundStyle(MacTweaksPalette.muted)
                    Text("No matching settings").font(.system(size: 16, weight: .semibold)).foregroundStyle(MacTweaksPalette.text)
                    Text("Try a setting, category, or related word.").font(.system(size: 12)).foregroundStyle(MacTweaksPalette.secondary)
                    MacTweaksBorderedButton("Clear search") { search = "" }.padding(.top, 8)
                }
                .frame(maxWidth: .infinity, minHeight: 410)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                    ForEach(results) { item in searchResultPanel(item) }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultPanel(_ item: TweakItem) -> some View {
        let category = category(for: item)
        MacTweaksPanel(item.title, glyph: category.glyph) {
            if item.id == "mic-lock" {
                MacTweaksInlineRow("Enabled") {
                    Toggle("Mic Lock", isOn: Binding(get: { micLock.isEnabled }, set: micLock.setEnabled))
                        .labelsHidden().toggleStyle(MacTweaksToggleStyle())
                        .accessibilityLabel("Mic Lock")
                }
            } else if item.id == "helper.keep-awake" {
                MacTweaksInlineRow("Keep this Mac awake") {
                    Toggle("Keep this Mac awake", isOn: Binding(
                        get: { awake.configuration.mode != .passive },
                        set: { awake.setMode($0 ? .indefinite : .passive) }
                    )).labelsHidden().toggleStyle(MacTweaksToggleStyle())
                        .accessibilityLabel("Keep this Mac awake")
                }
            } else {
                preferenceRows(item)
            }
            MacTweaksRowDivider()
            MacTweaksPreviewView(kind: category.preview).frame(height: 150)
        }
    }

    private var modifiedPage: some View {
        Group {
            if modifiedEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .light)).foregroundStyle(MacTweaksPalette.muted)
                    Text("No modified settings").font(.system(size: 16, weight: .semibold)).foregroundStyle(MacTweaksPalette.text)
                    Text("Settings changed with Mac Tweaks will appear here.").font(.system(size: 12)).foregroundStyle(MacTweaksPalette.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 390)
            } else {
                MacTweaksPanel("Modified settings", glyph: .apps) {
                    HStack {
                        Text("Setting").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Current").frame(width: 170, alignment: .leading)
                        Text("Original").frame(width: 170, alignment: .leading)
                        Color.clear.frame(width: 28)
                    }
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(MacTweaksPalette.muted)
                    .padding(.horizontal, 16).frame(height: 34)
                    ForEach(MacTweaksCategory.all) { category in
                        let entries = modifiedEntries.filter { $0.category.id == category.id }
                        if !entries.isEmpty {
                            Rectangle().fill(MacTweaksPalette.line).frame(height: 1)
                            Button { navigate(to: category.id) } label: {
                                HStack(spacing: 8) {
                                    MacTweaksGlyph(name: category.glyph).frame(width: 13, height: 13)
                                    Text(category.title).font(.system(size: 11, weight: .semibold))
                                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(MacTweaksPalette.secondary)
                                .padding(.horizontal, 16).frame(height: 32)
                            }.buttonStyle(MacTweaksHoverButtonStyle(cornerRadius: 0))
                            ForEach(entries) { entry in modifiedRow(entry) }
                        }
                    }
                }
            }
        }
    }

    private func modifiedRow(_ entry: MacTweaksModifiedEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.field.label).font(.system(size: 12)).foregroundStyle(MacTweaksPalette.text.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(MacTweaksPreferenceValue.label(for: TweakPreferenceStore.shared.selectedChoice(for: entry.field), field: entry.field))
                .frame(width: 170, alignment: .leading)
            Text(MacTweaksPreferenceValue.label(for: TweakPreferenceStore.shared.originalChoice(for: entry.field) ?? -2, field: entry.field))
                .frame(width: 170, alignment: .leading)
            Button {
                do {
                    try TweakPreferenceStore.shared.restore([entry.field])
                    preferenceRevision += 1
                    showNotice(restoredNotice(for: entry))
                    if modifiedEntries.count == 1 { selectedPage = entry.category.id }
                } catch { showError(error.localizedDescription) }
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10)).frame(width: 26, height: 24)
            }
            .buttonStyle(MacTweaksHoverButtonStyle())
            .accessibilityLabel("Reset \(entry.field.label)")
        }
        .font(.system(size: 11)).foregroundStyle(MacTweaksPalette.secondary)
        .padding(.horizontal, 16).frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(MacTweaksPalette.line).frame(height: 1).padding(.leading, 16) }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacTweaksPanel("Mac Tweaks", glyph: .apps) {
                HStack(spacing: 20) {
                    Image("MacTweaksLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mac Tweaks").font(.system(size: 24, weight: .medium)).foregroundStyle(MacTweaksPalette.text)
                        Text("Small controls for the way you use your Mac.").font(.system(size: 12)).foregroundStyle(MacTweaksPalette.secondary)
                        Text("Part of MacPowerToys").font(.system(size: 11)).foregroundStyle(MacTweaksPalette.muted)
                    }
                    Spacer()
                }
                .padding(24)
                MacTweaksRowDivider()
                aboutRow("Version", value: appVersion)
                MacTweaksRowDivider()
                aboutRow("Preferences", value: "Exact-value backup and restore")
                MacTweaksRowDivider()
                aboutRow("System access", value: "Requested only when selected")
            }
            .frame(width: 620)
            MacTweaksPanel("Keyboard", glyph: .input) {
                aboutRow("Search", value: "⌘ K")
                MacTweaksRowDivider()
                aboutRow("Clear search or close a menu", value: "Esc")
                MacTweaksRowDivider()
                aboutRow("Move between options", value: "←  →")
            }
            .frame(width: 620)
            HStack {
                Spacer()
                MacTweaksBorderedButton("Copy app details", symbol: "doc.on.doc") { copyAppDetails() }
            }
            .frame(width: 620)
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(MacTweaksPalette.secondary)
            Spacer()
            Text(value).foregroundStyle(MacTweaksPalette.muted)
        }
        .font(.system(size: 12)).padding(.horizontal, 16).frame(height: 44)
    }

    private func preferencePreviewPanel(
        _ title: String,
        glyph: MacTweaksGlyphName,
        itemIDs: [String],
        preview: MacTweaksPreviewKind
    ) -> some View {
        MacTweaksPanel(title, glyph: glyph) {
            preferenceRows(itemIDs)
            MacTweaksRowDivider()
            MacTweaksPreviewView(kind: preview)
        }
    }

    private func preferencePanel(_ title: String, glyph: MacTweaksGlyphName, itemIDs: [String]) -> some View {
        MacTweaksPanel(title, glyph: glyph) { preferenceRows(itemIDs) }
    }

    @ViewBuilder
    private func preferenceRows(_ itemIDs: [String]) -> some View {
        let items = itemIDs.map(item(for:)).filter(shouldShow)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            preferenceRows(item)
            if index < items.count - 1 { MacTweaksRowDivider() }
        }
    }

    private func preferenceRows(_ item: TweakItem) -> some View {
        MacTweaksPreferenceRows(
            itemID: item.id,
            fields: TweakPreferences.fields(for: item.id),
            summary: item.summary,
            revision: preferenceRevision,
            onChanged: preferenceChanged,
            onError: showError
        )
    }

    private func item(for id: String) -> TweakItem {
        if id == "mic-lock" { return TweakSearch.micLock }
        return TweakCatalog.items.first { $0.id == id }!
    }

    private func shouldShow(_ item: TweakItem) -> Bool {
        if item.id == "mic-lock" || item.id == "helper.keep-awake" { return true }
        let fields = TweakPreferences.fields(for: item.id)
        return TweakPreferences.supportsWrites(for: item.id) || TweakPreferenceStore.shared.hasBackup(for: fields)
    }

    private func category(for item: TweakItem) -> MacTweaksCategory {
        MacTweaksCategory.all.first { $0.itemIDs.contains(item.id) } ?? MacTweaksCategory.all[0]
    }

    private func groupTitle(for category: MacTweaksCategory) -> String {
        switch category.id {
        case "finder": "Files & navigation"
        case "windows": "Window behavior"
        case "screenshots": "Capture preferences"
        case "apps": "Application behavior"
        case "menubar": "Menu bar preferences"
        default: category.title
        }
    }

    private func previewTitle(for category: MacTweaksCategory) -> String {
        category.id == "windows" ? "Open & close" : "\(category.title) preview"
    }

    private func navigate(to page: String) {
        search = ""
        searchFocused = false
        selectedPage = page
    }

    private func preferenceChanged(_ itemID: String) {
        preferenceRevision += 1
        showNotice(activationNotice(for: itemID))
    }

    private func activationNotice(for itemID: String) -> MacTweaksNotice {
        if itemID.hasPrefix("dock.") {
            return .init(message: "Saved. Restart Dock when you are ready.", actionTitle: "Restart Dock", targetBundleIdentifier: "com.apple.dock", targetName: "Dock")
        }
        if itemID.hasPrefix("finder.") && itemID != "finder.network-metadata" {
            return .init(message: "Saved. Restart Finder when you are ready.", actionTitle: "Restart Finder", targetBundleIdentifier: "com.apple.finder", targetName: "Finder")
        }
        switch itemID {
        case "finder.network-metadata": return .init(message: "Saved. Sign out and back in to apply this Finder change.")
        case "terminal.pointer-focus": return .init(message: "Saved. Reopen Terminal after saving your sessions.")
        case _ where itemID.hasPrefix("screenshots."): return .init(message: "Saved. Take a new screenshot to check the result.")
        case "menubar.spacing": return .init(message: "Saved. Sign out or reopen affected menu bar apps to apply it.")
        default: return .init(message: "Saved. Newly opened apps will use this setting.")
        }
    }

    private func showError(_ message: String) {
        showNotice(.init(message: message, isError: true))
    }

    private func refreshMicrophones() {
        if !reduceMotion {
            withAnimation(.linear(duration: 0.45)) { refreshRotation += 360 }
        }
        micLock.refresh()
        let count = micLock.devices.count
        showNotice(.init(message: count == 1 ? "1 input device refreshed." : "\(count) input devices refreshed."))
    }

    private func showNotice(_ newNotice: MacTweaksNotice) {
        noticeTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { notice = newNotice }
        noticeTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.14)) { notice = nil }
        }
    }

    private func noticeView(_ notice: MacTweaksNotice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? MacTweaksPalette.accent : Color(white: 0.72))
            Text(notice.message).font(.system(size: 11)).lineLimit(2)
            if let title = notice.actionTitle,
               let bundleID = notice.targetBundleIdentifier,
               let name = notice.targetName {
                Button(title) { restartRequest = (name, bundleID) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTweaksPalette.text)
            }
            Button { self.notice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9)).frame(width: 20, height: 20)
            }.buttonStyle(MacTweaksHoverButtonStyle()).accessibilityLabel("Dismiss")
        }
        .foregroundStyle(MacTweaksPalette.secondary)
        .padding(.horizontal, 12).frame(minHeight: 40)
        .background(Color(red: 0.17, green: 0.17, blue: 0.17), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func restartRequestedApp() {
        guard let request = restartRequest else { return }
        restartRequest = nil
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: request.bundleID)
        guard !apps.isEmpty else { showNotice(.init(message: "\(request.name) is not running.")); return }
        let accepted = apps.allSatisfy { $0.terminate() }
        showNotice(.init(message: accepted ? "\(request.name) is restarting." : "\(request.name) declined the restart. Your setting remains saved."))
    }

    private func resetAllModified() {
        let fields = modifiedEntries.map(\.field)
        do {
            try TweakPreferenceStore.shared.restore(fields)
            preferenceRevision += 1
            selectedPage = "dock"
            showNotice(.init(message: "All Mac Tweaks changes were restored. Restart affected apps or sign out when convenient."))
        } catch { showError(error.localizedDescription) }
    }

    private func restoredNotice(for entry: MacTweaksModifiedEntry) -> MacTweaksNotice {
        var result = activationNotice(for: entry.item.id)
        let suffix = result.message.replacingOccurrences(of: "Saved. ", with: "")
        result = .init(
            message: "\(entry.field.label) restored. \(suffix)",
            actionTitle: result.actionTitle,
            targetBundleIdentifier: result.targetBundleIdentifier,
            targetName: result.targetName
        )
        return result
    }

    private var currentMicrophoneName: String {
        micLock.devices.first(where: { $0.id == micLock.currentUID })?.name ?? "No input available"
    }

    private func microphoneMenu(index: Int) -> some View {
        let saved = micLock.savedInputs[index]
        return Menu {
            Button("None") { micLock.setSavedInput(nil, at: index) }
            if let saved, !micLock.devices.contains(where: { $0.id == saved.uid }) {
                Button("\(saved.name) (Unavailable)") {}.disabled(true)
                Divider()
            }
            ForEach(micLock.devices) { device in
                Button(device.name) { micLock.setSavedInput(device.id, at: index) }
            }
        } label: {
            HStack {
                Text(saved?.name ?? "None").lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .font(.system(size: 11)).foregroundStyle(MacTweaksPalette.secondary)
            .padding(.horizontal, 10).frame(width: 218, height: 28)
            .background(MacTweaksPalette.panelRaised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(MacTweaksPalette.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(!micLock.isEnabled)
        .accessibilityLabel(index == 0 ? "Primary microphone" : "Fallback \(index) microphone")
    }

    private var inputVolumeControl: some View {
        HStack(spacing: 8) {
            Slider(value: Binding(
                get: { Double(micLock.volume ?? 0) },
                set: { micLock.setVolume(Float($0)) }
            ), in: 0...1)
            .controlSize(.mini).frame(width: 138).disabled(micLock.volume == nil || micLock.muted == true)
            Text("\(Int((micLock.volume ?? 0) * 100))%")
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(MacTweaksPalette.secondary).frame(width: 30, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var inputLevelControl: some View {
        if meter.permission == .authorized {
            HStack(spacing: 8) {
                MacTweaksLevelMeter(level: meter.level).frame(width: 146, height: 9)
                MacTweaksBorderedButton(meter.level > 0 ? "Live" : "Test") { meter.start() }
            }
        } else if meter.permission == .notDetermined {
            MacTweaksBorderedButton("Test") { Task { await meter.requestAndStart() } }
        } else {
            MacTweaksBorderedButton("Microphone Settings") { meter.openMicrophoneSettings() }
        }
    }

    private var awakeDurationMenu: some View {
        let mode = AwakeQuickMode(configuration: awake.configuration)
        return Menu {
            Button("Off") { awake.setMode(.passive) }
            Button("Indefinitely") { awake.setMode(.indefinite) }
            Divider()
            Button("30 minutes") { awake.setMode(.timed, duration: 1_800) }
            Button("1 hour") { awake.setMode(.timed, duration: 3_600) }
            Button("2 hours") { awake.setMode(.timed, duration: 7_200) }
        } label: {
            HStack {
                Text(awakeDurationLabel(mode)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .font(.system(size: 11)).foregroundStyle(MacTweaksPalette.secondary)
            .padding(.horizontal, 10).frame(width: 160, height: 28)
            .background(MacTweaksPalette.panelRaised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(MacTweaksPalette.line, lineWidth: 1))
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private func awakeDurationLabel(_ mode: AwakeQuickMode) -> String {
        switch mode {
        case .off: "Off"
        case .indefinite: "Indefinitely"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .custom: awake.statusText
        }
    }

    private func syncInputMonitoring() {
        meter.stop()
        guard selectedPage == "input", !isSearching else { return }
        meter.refreshPermission()
        if meter.permission == .authorized { meter.start() }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            opensAtLogin = SMAppService.mainApp.status == .enabled
            let message = SMAppService.mainApp.status == .requiresApproval
                ? "Allow MacPowerToys in Login Items to finish setup." : "Login setting saved."
            showNotice(.init(message: message))
        } catch {
            opensAtLogin = SMAppService.mainApp.status == .enabled
            showError("Could not change Login Items: \(error.localizedDescription)")
        }
    }

    private func reviveAudio() {
        showNotice(.init(message: "Restarting the Mac audio service…"))
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            let result: String
            let succeeded: Bool
            do {
                try process.run()
                process.waitUntilExit()
                let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                succeeded = process.terminationStatus == 0
                result = succeeded ? "Audio restarted. Devices refreshed." :
                    (detail.isEmpty ? "Audio restart was cancelled." : detail)
            } catch {
                succeeded = false
                result = "Could not restart audio: \(error.localizedDescription)"
            }
            await MainActor.run {
                micLock.refresh()
                if succeeded { showNotice(.init(message: result)) } else { showError(result) }
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func copyAppDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Mac Tweaks \(appVersion)\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)", forType: .string)
        showNotice(.init(message: "App details copied."))
    }
}

private struct MacTweaksSidebarButton: View {
    let category: MacTweaksCategory
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let normal = Color(white: 0.714)
        let active = Color(white: 0.94)
        Button(action: action) {
            HStack(spacing: 9) {
                MacTweaksGlyph(name: category.glyph, color: selected ? active : normal)
                    .frame(width: 15, height: 15)
                Text(category.title).font(.system(size: 12, weight: .regular))
                Spacer()
            }
            .foregroundStyle(selected ? active : normal)
            .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            .background(selected ? Color.white.opacity(0.105) : hovering ? Color.white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).focusEffectDisabled().onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(category.title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MacTweaksBottomSidebarButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let normal = Color(white: 0.714)
        let active = Color(white: 0.94)
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 11)).frame(width: 15)
                Text(title).font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(enabled ? (selected ? active : normal) : Color(white: 0.396))
            .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            .background(selected ? Color.white.opacity(0.105) : hovering && enabled ? Color.white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).disabled(!enabled).focusEffectDisabled().onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct MacTweaksSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Button { isFocused.wrappedValue = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(MacTweaksPalette.muted)
                    .frame(width: 12, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            TextField("Search", text: $text)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(MacTweaksPalette.text)
                .focused(isFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Search all tweaks")
            if text.isEmpty {
                Button { isFocused.wrappedValue = true } label: {
                    Text("⌘ K")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTweaksPalette.muted)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            } else {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(MacTweaksPalette.muted)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: isFocused.wrappedValue ? 0.169 : 0.145))
                Button { isFocused.wrappedValue = true } label: {
                    Color.clear.contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.22), lineWidth: 1))
        .animation(.easeOut(duration: 0.09), value: isFocused.wrappedValue)
        .accessibilityIdentifier("mac-tweaks.search")
    }
}

private struct MacTweaksStandalonePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .background { ZStack { MacTweaksPalette.panel; MacTweaksDither(strength: 0.10) } }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MacTweaksPalette.line, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MacTweaksInlineRow<Control: View>: View {
    let title: String
    let control: Control
    init(_ title: String, @ViewBuilder control: () -> Control) { self.title = title; self.control = control() }
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 12)).foregroundStyle(MacTweaksPalette.text.opacity(0.9)).lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 16).frame(height: 44)
    }
}

private struct MacTweaksBorderedButton: View {
    let title: String
    let symbol: String?
    let action: () -> Void
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(MacTweaksPalette.secondary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(MacTweaksPalette.line, lineWidth: 1))
        }.buttonStyle(MacTweaksHoverButtonStyle())
    }
}

private struct MacTweaksLevelMeter: View {
    let level: Float
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Float(index) / 20 < level ? Color(white: 0.72) : Color.white.opacity(0.10))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

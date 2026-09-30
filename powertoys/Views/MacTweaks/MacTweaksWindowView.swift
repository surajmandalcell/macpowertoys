import AppKit
import AVFoundation
import OnePlusUI
import ServiceManagement
import SwiftUI

enum MacTweaksLayout {
    static let windowSize = NSSize(width: 1_120, height: 826)
    static let contentSize = NSSize(
        width: windowSize.width,
        height: windowSize.height - UtilityLayout.hiddenTitlebarBottomSurplus
    )
    static let sidebarWidth: CGFloat = 200
    static let titlebarHeight = OnePlusMetrics.titleRow
    static let contentInset = OnePlusMetrics.gutter
    static let panelGap = OnePlusMetrics.cardGap
    static let trafficLightVerticalOffset = OnePlusMetrics.trafficLightVerticalOffset
}

private enum MacTweaksModifiedTableLayout {
    static let valueColumn = OnePlusMetrics.controlColumn + OnePlusMetrics.spacing[4]
}

private struct MacTweaksCategory: Identifiable {
    let id: String
    let title: String
    let group: String
    let glyph: MacTweaksGlyphName
    let itemIDs: [String]
    let preview: MacTweaksPreviewKind

    var systemImage: String {
        switch id {
        case "input": "slider.horizontal.3"
        case "dock": "dock.rectangle"
        case "finder": "folder"
        case "windows": "macwindow.on.rectangle"
        case "screenshots": "camera.viewfinder"
        case "apps": "square.grid.2x2"
        case "power": "bolt"
        case "menu-bar": "menubar.rectangle"
        default: "slider.horizontal.3"
        }
    }

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
        .init(id: "menu-bar", title: "Menu bar", group: "System", glyph: .menubar,
              itemIDs: ["menubar.spacing"], preview: .menubar)
    ]
}

private struct MacTweaksModifiedEntry: Identifiable {
    let category: MacTweaksCategory
    let item: TweakItem
    let field: TweakPreferenceField
    let currentSelection: Int
    let originalSelection: Int
    var id: String { field.identity }
}

struct MacTweaksSettingsContent: View {
    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Preferences", systemImage: "slider.horizontal.3")
                OnePlusSettingRow(
                    "System preferences",
                    caption: "Adjust input, Dock, Finder, windows, screenshots, apps, power, and menu bar.",
                    separator: false
                ) {
                    Button("Open Mac Tweaks") {
                        ToolActionRouter.shared.open(toolID: "mac-tweaks")
                    }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                }
            }
        }
    }
}

struct MacTweaksWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var search = ""
    @State private var selectedPage = "dock"
    @State private var preferenceRevision = 0
    @State private var preferenceSelections: [String: Int] = [:]
    @State private var modifiedIdentities: Set<String> = []
    @State private var backedUpIdentities: Set<String> = []
    @State private var modifiedEntries: [MacTweaksModifiedEntry] = []
    @State private var notice: MacTweaksNotice?
    @State private var noticeTask: Task<Void, Never>?
    @State private var restartRequest: (name: String, bundleID: String)?
    @State private var showsResetAllConfirmation = false
    @State private var showsReviveConfirmation = false
    @State private var micLock = MicLockService.shared
    @State private var meter = MicInputLevelMonitor()
    @State private var awake = AwakeService.shared
    @State private var opensAtLogin = false
    @State private var refreshRotation = 0.0
    @State private var audioRevive = AudioReviveService()

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
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OnePlusWindowRoot(canvas: .macTweaks) { sidebar } content: { workspace }
            if let notice {
                noticeView(notice)
                    .padding(OnePlusMetrics.gutter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(WindowAccessor(identifier: "mac-tweaks"))
        .buttonStyle(OnePlusButtonStyle())
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .task {
            await Task.yield()
            micLock.setWindowOpen(true)
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onDisappear {
            noticeTask?.cancel()
            audioRevive.cancel()
            meter.stop()
            micLock.setWindowOpen(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            opensAtLogin = SMAppService.mainApp.status == .enabled
            preferenceRevision &+= 1
            if selectedPage == "input" { meter.refreshPermission() }
        }
        .task(id: inputMonitoringID) {
            await Task.yield()
            syncInputMonitoring()
            guard selectedPage == "input", !isSearching else { return }
            while !Task.isCancelled {
                micLock.refreshControls()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
        .task(id: preferenceRevision) { await reloadPreferenceState() }
        .onExitCommand { if !search.isEmpty { search = "" } }
        .onOpenToolPage("mac-tweaks") { pageID in
            let pageIDs = Set(MacTweaksCategory.all.map(\.id) + ["modified", "about"])
            if pageIDs.contains(pageID) { navigate(to: pageID) }
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
            Text("Mac Tweaks restores backed-up values. Other listed values return to their system defaults.")
        }
        .confirmationDialog("Restart Mac audio?", isPresented: $showsReviveConfirmation) {
            Button("Revive Audio") { reviveAudio() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Audio in other apps may stop briefly. macOS will request administrator approval.")
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "Mac Tweaks") {
            OnePlusSidebarSearch("Search tweaks", text: $search,
                                 accessibilityIdentifier: "mac-tweaks.search")
        } navigation: {
            OnePlusNavCaption("Everyday")
            sidebarGroup("Everyday")
            OnePlusNavCaption("System")
            sidebarGroup("System")
        } bottom: {
            OnePlusNavRow(
                "Modified",
                systemImage: "arrow.counterclockwise",
                selected: !isSearching && selectedPage == "modified",
                count: modifiedEntries.count,
                muted: modifiedEntries.isEmpty
            ) {
                if !modifiedEntries.isEmpty { navigate(to: "modified") }
            }
            OnePlusNavRow(
                "About",
                systemImage: "info.circle",
                selected: !isSearching && selectedPage == "about"
            ) { navigate(to: "about") }
            .accessibilityIdentifier("mac-tweaks.about")
        }
    }

    private func sidebarGroup(_ name: String) -> some View {
        Group {
            ForEach(MacTweaksCategory.all.filter { $0.group == name }) { category in
                OnePlusNavRow(
                    category.title,
                    systemImage: category.systemImage,
                    selected: !isSearching && selectedPage == category.id
                ) {
                    navigate(to: category.id)
                }
                .accessibilityIdentifier("mac-tweaks.category.\(category.title)")
            }
        }
    }

    private var workspace: some View {
        OnePlusPage(scrolls: isSearching || selectedPage != "modified") {
            OnePlusPageHeader(title: pageTitle) {
                if !isSearching && selectedPage == "modified" {
                    Button("Reset all", systemImage: "arrow.counterclockwise") {
                        showsResetAllConfirmation = true
                    }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(modifiedEntries.isEmpty)
                }
            }
        } content: {
            Group {
                if isSearching { searchPage }
                else if selectedPage == "modified" { modifiedPage }
                else if selectedPage == "about" { aboutPage }
                else { categoryPage }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .frame(height: 344)
            HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
                preferencePanel("Layout & appearance", glyph: .layers,
                                itemIDs: ["dock.lock-size", "dock.lock-contents", "dock.hidden-app-dimming", "dock.stack-selection", "dock.switcher-displays"],
                                fillsHeight: true)
                MacTweaksPanel("Stack & app switcher", glyph: .dock, fillsHeight: true) {
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
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .accessibilityLabel("Mic Lock")
                        .accessibilityIdentifier("mac-tweaks.mic-lock.enabled")
                }
            }
            HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
                MacTweaksPanel("Input priority", glyph: .priority) {
                    ForEach(0..<4, id: \.self) { index in
                        MacTweaksInlineRow(
                            index == 0 ? "Primary" : "Fallback \(index)",
                            controlWidth: OnePlusMetrics.wideControlColumn,
                            separator: index < 3
                        ) {
                            microphoneMenu(index: index)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { refreshMicrophones() } label: {
                        Image(systemName: "arrow.clockwise")
                            .onePlusText(.caption)
                            .rotationEffect(.degrees(refreshRotation))
                            .frame(width: OnePlusMetrics.controlHeight, height: OnePlusMetrics.controlHeight)
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon))
                    .foregroundStyle(MacTweaksPalette.secondary)
                    .disabled(!micLock.isEnabled)
                    .help("Refresh devices")
                    .accessibilityLabel("Refresh devices")
                    .accessibilityIdentifier("mac-tweaks.mic-lock.refresh")
                    .padding(.top, OnePlusMetrics.spacing[2])
                    .padding(.trailing, OnePlusMetrics.spacing[4])
                }
                MacTweaksPanel("Current input", glyph: .microphone) {
                    MacTweaksInlineRow("Microphone", separator: true) {
                        Text(currentMicrophoneName).lineLimit(1)
                            .onePlusText(.control)
                    }
                    if micLock.volume != nil {
                        MacTweaksInlineRow("Input volume", separator: true) { inputVolumeControl }
                    }
                    if micLock.muted != nil {
                        MacTweaksInlineRow("Mute microphone", separator: true) {
                            Toggle("Mute microphone", isOn: Binding(get: { micLock.muted ?? false }, set: micLock.setMuted))
                                .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                                .accessibilityLabel("Mute microphone")
                        }
                    }
                    MacTweaksInlineRow("Input level", controlWidth: OnePlusMetrics.wideControlColumn) { inputLevelControl }
                }
            }
            .frame(height: 216)
            HStack(spacing: MacTweaksLayout.panelGap) {
                MacTweaksStandalonePanel {
                    MacTweaksInlineRow("Open at login") {
                        Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpenAtLogin))
                            .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                            .accessibilityLabel("Open at login")
                    }
                }
                MacTweaksStandalonePanel {
                    MacTweaksInlineRow("Audio service") {
                        MacTweaksBorderedButton("Revive Audio", symbol: "lock") { showsReviveConfirmation = true }
                            .disabled(audioRevive.isRunning)
                    }
                }
            }
            preferencePanel("Keyboard", glyph: .keyboard, itemIDs: ["input.press-hold"])
        }
    }

    private var powerPage: some View {
        HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
            MacTweaksPanel("Power preferences", glyph: .power) {
                MacTweaksInlineRow("Keep this Mac awake", separator: true) {
                    Toggle("Keep this Mac awake", isOn: Binding(
                        get: { awake.configuration.mode != .passive },
                        set: { enabled in
                            SettingsManager.shared.setToolEnabled(true, for: "awake")
                            awake.setMode(enabled ? .indefinite : .passive)
                        }
                    )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .accessibilityLabel("Keep this Mac awake")
                }
                MacTweaksInlineRow("Duration", separator: true) { awakeDurationMenu }
                MacTweaksInlineRow("Keep display on", separator: true) {
                    Toggle("Keep display on", isOn: Binding(get: { awake.configuration.keepDisplayOn }, set: awake.setKeepDisplayOn))
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .accessibilityLabel("Keep display on")
                }
                MacTweaksInlineRow("Status") {
                    Text(awakeStatusText).onePlusText(.mono)
                        .foregroundStyle(awake.assertionError == nil ? MacTweaksPalette.secondary : MacTweaksPalette.accent)
                        .lineLimit(1)
                }
            }
            .frame(width: 442)
            MacTweaksPanel("Power preview", glyph: .power) {
                MacTweaksPreviewView(kind: .power)
            }
            .frame(height: 300)
        }
    }

    private func genericPage(_ category: MacTweaksCategory) -> some View {
        HStack(alignment: .top, spacing: MacTweaksLayout.panelGap) {
            preferencePanel(groupTitle(for: category), glyph: category.glyph, itemIDs: category.itemIDs)
                .frame(width: 442)
            MacTweaksPanel(previewTitle(for: category), glyph: category.glyph) {
                MacTweaksPreviewView(kind: category.preview)
            }
            .frame(height: 280)
        }
    }

    private var searchPage: some View {
        let results = TweakSearch.results(for: trimmedSearch, in: allWorkingItems)
        let hasInputResult = results.contains { category(for: $0).id == "input" }
        let columns = hasInputResult
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 16), GridItem(.flexible())]
        return Group {
            if results.isEmpty {
                OnePlusEmptyState(
                    "No matching settings",
                    systemImage: "magnifyingglass",
                    caption: "Try a setting, category, or related word."
                ) {
                    Button("Clear search") { search = "" }
                        .buttonStyle(OnePlusButtonStyle(.neutral))
                }
                .frame(maxWidth: .infinity, minHeight: 410)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
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
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .accessibilityLabel("Mic Lock")
                }
            } else if item.id == "helper.keep-awake" {
                MacTweaksInlineRow("Keep this Mac awake") {
                    Toggle("Keep this Mac awake", isOn: Binding(
                        get: { awake.configuration.mode != .passive },
                        set: { awake.setMode($0 ? .indefinite : .passive) }
                    )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .accessibilityLabel("Keep this Mac awake")
                }
            } else {
                preferenceRows(item)
            }
            MacTweaksRowDivider()
            MacTweaksPreviewView(kind: category.preview)
                .aspectRatio(600 / 304, contentMode: .fit)
        }
    }

    private var modifiedPage: some View {
        Group {
            if modifiedEntries.isEmpty {
                OnePlusEmptyState(
                    "No modified settings",
                    systemImage: "checkmark.circle",
                    caption: "Settings that differ from their defaults appear here."
                )
                .frame(maxWidth: .infinity, minHeight: 390)
            } else {
                MacTweaksPanel("Modified settings", glyph: .apps) {
                    HStack(spacing: OnePlusMetrics.spacing[3]) {
                        Text("Setting").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Current").frame(width: MacTweaksModifiedTableLayout.valueColumn, alignment: .leading)
                        Text("Original").frame(width: MacTweaksModifiedTableLayout.valueColumn, alignment: .leading)
                        Color.clear.frame(width: OnePlusMetrics.controlHeight)
                    }
                    .padding(.horizontal, OnePlusMetrics.spacing[1])
                    .onePlusTableHeader()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(MacTweaksCategory.all) { category in
                                let entries = modifiedEntries.filter { $0.category.id == category.id }
                                if !entries.isEmpty {
                                    Rectangle().fill(MacTweaksPalette.line).frame(height: 1)
                                    Button { navigate(to: category.id) } label: {
                                        HStack(spacing: 8) {
                                            MacTweaksGlyph(name: category.glyph).frame(width: 13, height: 13)
                                            Text(category.title).onePlusText(.cardTitle)
                                            Image(systemName: "chevron.right").onePlusText(.caption)
                                            Spacer()
                                        }
                                        .foregroundStyle(MacTweaksPalette.secondary)
                                        .padding(.horizontal, OnePlusMetrics.cardPadding)
                                        .frame(height: OnePlusMetrics.navRowHeight)
                                    }.buttonStyle(OnePlusInteractionStyle())
                                    ForEach(entries) { entry in modifiedRow(entry) }
                                }
                            }
                        }
                    }
                    .onePlusScrollIndicators()
                }
            }
        }
    }

    private func modifiedRow(_ entry: MacTweaksModifiedEntry) -> some View {
        HStack(spacing: OnePlusMetrics.spacing[3]) {
            Text(entry.field.label).onePlusText(.row)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(MacTweaksPreferenceValue.label(for: entry.currentSelection, field: entry.field))
                .frame(width: MacTweaksModifiedTableLayout.valueColumn, alignment: .leading)
            Text(MacTweaksPreferenceValue.label(for: entry.originalSelection, field: entry.field))
                .frame(width: MacTweaksModifiedTableLayout.valueColumn, alignment: .leading)
            Button {
                do {
                    if backedUpIdentities.contains(entry.field.identity) {
                        try TweakPreferenceStore.shared.restore([entry.field])
                    } else {
                        try TweakPreferenceStore.shared.apply(
                            [entry.field],
                            selections: [entry.field.identity: -1]
                        )
                    }
                    preferenceRevision += 1
                    showNotice(restoredNotice(for: entry))
                    if modifiedEntries.count == 1 { selectedPage = entry.category.id }
                } catch { showError(error.localizedDescription) }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(OnePlusButtonStyle(.icon))
            .frame(width: OnePlusMetrics.controlHeight)
            .accessibilityLabel("Reset \(entry.field.label)")
        }
        .onePlusText(.control)
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.settingRow)
        .overlay(alignment: .top) {
            OnePlusColor.lineSoft.frame(height: 1).padding(.leading, OnePlusMetrics.cardPadding)
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnePlusCard {
                HStack(spacing: 20) {
                    Image("MacTweaksLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mac Tweaks").onePlusText(.pageTitle)
                        Text("Small controls for the way you use your Mac.").onePlusText(.row)
                        Text("Part of MacPowerToys").onePlusText(.caption)
                    }
                    Spacer()
                }
                .padding(OnePlusMetrics.cardPadding)
                MacTweaksRowDivider()
                aboutRow("Version", value: appVersion, separator: true)
                aboutRow("Preferences", value: "Exact-value backup and restore", separator: true)
                aboutRow("System access", value: "Requested only when selected")
            }
            .frame(width: 620)
            MacTweaksPanel("Keyboard", glyph: .keyboard) {
                aboutRow("Search", value: "⌘ K", separator: true)
                aboutRow("Clear search or close a menu", value: "Esc", separator: true)
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

    private func aboutRow(_ label: String, value: String, separator: Bool = false) -> some View {
        OnePlusSettingRow(label, separator: separator) {
            Text(value).onePlusText(.control)
        }
    }

    private func preferencePreviewPanel(
        _ title: String,
        glyph: MacTweaksGlyphName,
        itemIDs: [String],
        preview: MacTweaksPreviewKind
    ) -> some View {
        MacTweaksPanel(title, glyph: glyph) {
            preferenceRows(itemIDs, separator: true)
            MacTweaksPreviewView(kind: preview)
        }
    }

    private func preferencePanel(_ title: String, glyph: MacTweaksGlyphName, itemIDs: [String], fillsHeight: Bool = false) -> some View {
        MacTweaksPanel(title, glyph: glyph, fillsHeight: fillsHeight) { preferenceRows(itemIDs) }
    }

    @ViewBuilder
    private func preferenceRows(_ itemIDs: [String], separator: Bool = false) -> some View {
        let items = itemIDs.map(item(for:)).filter(shouldShow)
        let controlWidth = items.flatMap { TweakPreferences.fields(for: $0.id) }.contains { $0.choices.count == 2 }
            ? OnePlusMetrics.wideControlColumn : OnePlusMetrics.controlColumn
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            preferenceRows(item, controlWidth: controlWidth, separator: separator || index < items.count - 1)
        }
    }

    private func preferenceRows(_ item: TweakItem, controlWidth: CGFloat? = nil, separator: Bool = false) -> some View {
        let fields = TweakPreferences.fields(for: item.id)
        let width = controlWidth ?? (fields.contains { $0.choices.count == 2 }
            ? OnePlusMetrics.wideControlColumn : OnePlusMetrics.controlColumn)
        return MacTweaksPreferenceRows(
            itemID: item.id,
            fields: fields,
            controlWidth: width,
            separator: separator,
            summary: item.summary,
            revision: preferenceRevision,
            selections: preferenceSelections,
            modifiedIdentities: modifiedIdentities,
            backedUpIdentities: backedUpIdentities,
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
        return TweakPreferences.supportsWrites(for: item.id)
            || fields.contains { modifiedIdentities.contains($0.identity) }
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
        case "menu-bar": "Menu bar preferences"
        default: category.title
        }
    }

    private func previewTitle(for category: MacTweaksCategory) -> String {
        category.id == "windows" ? "Open & close" : "\(category.title) preview"
    }

    private func navigate(to page: String) {
        search = ""
        selectedPage = page
    }

    private func preferenceChanged(_ itemID: String) {
        preferenceRevision += 1
        showNotice(activationNotice(for: itemID))
    }

    private func reloadPreferenceState() async {
        let candidates = MacTweaksCategory.all.flatMap { category in
            category.itemIDs.flatMap { id in
                let item = item(for: id)
                return TweakPreferences.fields(for: id).map { (category, item, $0) }
            }
        }
        let fields = candidates.map(\.2)
        let snapshot = await Task.detached(priority: .utility) {
            let store = TweakPreferenceStore()
            let originals = store.storedOriginalChoices(for: fields)
            let selections = Dictionary(uniqueKeysWithValues: fields.map {
                ($0.identity, TweakPreferenceStore.readSelectedChoice(for: $0))
            })
            return (originals, selections)
        }.value
        guard !Task.isCancelled else { return }
        let originals = snapshot.0
        let selections = snapshot.1
        preferenceSelections = selections
        backedUpIdentities = Set(originals.keys)
        modifiedIdentities = Set(candidates.compactMap { _, _, field in
            field.differsFromDefault(selections[field.identity] ?? -1) ? field.identity : nil
        })
        modifiedEntries = candidates.compactMap { category, item, field in
            let current = selections[field.identity] ?? -1
            guard field.differsFromDefault(current) else { return nil }
            return MacTweaksModifiedEntry(
                category: category,
                item: item,
                field: field,
                currentSelection: current,
                originalSelection: originals[field.identity] ?? -1
            )
        }
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
        micLock.refresh { count in
            showNotice(.init(message: count == 1 ? "1 input device refreshed." : "\(count) input devices refreshed."))
        }
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
        OnePlusBanner(notice.message, tone: notice.isError ? .error : .information) {
            if let title = notice.actionTitle,
               let bundleID = notice.targetBundleIdentifier,
               let name = notice.targetName {
                Button(title) { restartRequest = (name, bundleID) }
                    .buttonStyle(OnePlusButtonStyle(.ghost))
            }
            Button { self.notice = nil } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(OnePlusButtonStyle(.icon))
            .accessibilityLabel("Dismiss")
        }
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
        let backedUp = modifiedEntries.map(\.field).filter { backedUpIdentities.contains($0.identity) }
        let external = modifiedEntries.map(\.field).filter { !backedUpIdentities.contains($0.identity) }
        do {
            try TweakPreferenceStore.shared.restore(backedUp)
            try TweakPreferenceStore.shared.apply(
                external,
                selections: Dictionary(uniqueKeysWithValues: external.map { ($0.identity, -1) })
            )
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

    private var inputMonitoringID: String {
        "\(selectedPage)|\(isSearching)|\(micLock.currentUID ?? "")"
    }

    private func microphoneMenu(index: Int) -> some View {
        let saved = micLock.savedInputs[index]
        var choices = [("", "None")]
        if let saved, !micLock.devices.contains(where: { $0.id == saved.uid }) {
            choices.append((saved.uid, "\(saved.name) (Unavailable)"))
        }
        choices.append(contentsOf: micLock.devices.map { ($0.id, $0.name) })
        return OnePlusSelect(
            choices: choices,
            selection: Binding(
                get: { saved?.uid ?? "" },
                set: { micLock.setSavedInput($0.isEmpty ? nil : $0, at: index) }
            ),
            width: OnePlusMetrics.wideControlColumn,
            accessibilityLabel: index == 0 ? "Primary microphone" : "Fallback \(index) microphone"
        )
        .disabled(!micLock.isEnabled)
    }

    private var inputVolumeControl: some View {
        HStack(spacing: 8) {
            Slider(value: Binding(
                get: { Double(micLock.volume ?? 0) },
                set: { micLock.setVolume(Float($0)) }
            ), in: 0...1)
            .controlSize(.mini)
            .disabled(micLock.volume == nil || micLock.muted == true)
            HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.spacing[0]) {
                Text(Int((micLock.volume ?? 0) * 100).formatted())
                Text("%")
            }
            .onePlusText(.mono)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var inputLevelControl: some View {
        HStack(spacing: OnePlusMetrics.spacing[3]) {
            OnePlusSegmentBar(
                values: Array(repeating: 1, count: 20),
                colors: (0..<20).map { index in
                    meter.permission == .authorized && Float(index) / 20 < meter.level
                        ? OnePlusColor.chartLine : OnePlusColor.track
                }
            )
            .accessibilityLabel("Input level")
            .accessibilityValue("\(Int(meter.level * 100)) percent")
            Group {
                if meter.permission == .authorized {
                    MacTweaksBorderedButton(meter.level > 0 ? "Live" : "Test") { meter.start() }
                } else if meter.permission == .notDetermined {
                    MacTweaksBorderedButton("Test") { Task { await meter.requestAndStart() } }
                } else {
                    MacTweaksBorderedButton("Settings") { meter.openMicrophoneSettings() }
                        .accessibilityLabel("Microphone Settings")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var awakeDurationMenu: some View {
        let mode = AwakeQuickMode(configuration: awake.configuration)
        var choices: [(AwakeQuickMode, String)] = [
            (.off, "Off"),
            (.indefinite, "Indefinitely"),
            (.thirtyMinutes, "30 minutes"),
            (.oneHour, "1 hour")
        ]
        if mode == .custom { choices.append((.custom, awakeDurationLabel(mode))) }
        return OnePlusSelect(
            choices: choices,
            selection: Binding(
                get: { mode },
                set: {
                    switch $0 {
                    case .off: awake.setMode(.passive)
                    case .indefinite: awake.setMode(.indefinite)
                    case .thirtyMinutes: awake.setMode(.timed, duration: 1_800)
                    case .oneHour: awake.setMode(.timed, duration: 3_600)
                    case .custom: break
                    }
                }
            ),
            accessibilityLabel: "Awake duration"
        )
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

    private var awakeStatusText: String {
        switch AwakeQuickMode(configuration: awake.configuration) {
        case .off: "Inactive"
        case .indefinite: "Awake indefinitely"
        case .thirtyMinutes: "Awake for 30 minutes"
        case .oneHour: "Awake for 1 hour"
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
        audioRevive.restart { result in
            micLock.refresh()
            if result.succeeded { showNotice(.init(message: result.message)) }
            else { showError(result.message) }
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

private struct MacTweaksStandalonePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        OnePlusCard { content }
    }
}

private struct MacTweaksInlineRow<Control: View>: View {
    let title: String
    let controlWidth: CGFloat
    let separator: Bool
    let control: Control
    init(
        _ title: String,
        controlWidth: CGFloat = OnePlusMetrics.controlColumn,
        separator: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.controlWidth = controlWidth
        self.separator = separator
        self.control = control()
    }
    var body: some View {
        OnePlusSettingRow(title, controlWidth: controlWidth, separator: separator) { control }
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
            if let symbol { Label(title, systemImage: symbol) }
            else { Text(title) }
        }
        .buttonStyle(OnePlusButtonStyle(.neutral))
    }
}

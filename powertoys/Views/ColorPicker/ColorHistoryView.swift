import SwiftUI
import OnePlusUI

enum ColorPickerLayout {
    static let windowWidth = OnePlusWindowCanvas.colorPicker.size.width
    static let bodyHorizontalInset = OnePlusMetrics.appletGutter
    static let historyBaseHeight = OnePlusWindowCanvas.colorPicker.size.height - OnePlusMetrics.appletTitlebar
    static let maximumWindowHeight = OnePlusWindowCanvas.colorPicker.heightRange!.upperBound
    static let settingsHeight = maximumWindowHeight - OnePlusMetrics.appletTitlebar
    static let historyRowHeight = OnePlusMetrics.captionedSettingRow

    static func historyHeight(count: Int) -> CGFloat {
        min(maximumWindowHeight, historyBaseHeight + OnePlusMetrics.appletTitlebar
            + CGFloat(max(0, min(count, 5) - 1)) * historyRowHeight)
    }
}

struct ColorHistoryView: View {
    @State private var service = ColorPickerService.shared
    @State private var page = ColorPickerPage.history
    @State private var search = ""
    @State private var focusSearch = 0
    @State private var isCreatingProject = false
    @State private var newProjectName = ""

    private var samples: [ColorSample] {
        let samples = service.samples(in: service.selectedProjectID)
        guard !search.isEmpty else { return samples }
        return samples.filter { sample in
            ColorCopyFormat.allCases.contains { sample.string($0).localizedCaseInsensitiveContains(search) }
        }
    }

    private var selectedProjectName: String {
        service.projects.first { $0.id == service.selectedProjectID }?.name ?? "Unfiled"
    }

    private var windowHeight: CGFloat {
        switch page {
        case .history: ColorPickerLayout.historyHeight(count: samples.count)
        case .projects:
            min(ColorPickerLayout.maximumWindowHeight, OnePlusWindowCanvas.colorPicker.size.height
                + CGFloat(min(service.projects.count, 4) + (isCreatingProject ? 1 : 0)) * OnePlusMetrics.settingRow)
        case .settings: ColorPickerLayout.maximumWindowHeight
        }
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .colorPicker, sidebar: { EmptyView() }) {
            VStack(spacing: 0) {
                OnePlusAppletTitlebar(title: "Color Picker") {
                    Button("Pick Color") { service.pick() }
                        .buttonStyle(OnePlusButtonStyle(.primary))
                        .disabled(service.isPicking)
                        .help("Pick a color for \(selectedProjectName)")
                        .accessibilityIdentifier("color-picker.pick")
                }
                VStack(spacing: 0) {
                    if page != .settings { tabBar }
                    switch page {
                    case .history: history
                    case .projects: projects
                    case .settings:
                        OnePlusPage(layout: .applet, header: { EmptyView() }) {
                            ColorPickerSettingsView()
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .onePlusFloatingSettingsInset()
                .overlay(alignment: .bottomTrailing) {
                    OnePlusFloatingSettingsButton(isActive: page == .settings, help: page == .settings ? "Back to History" : "Settings") {
                        page = page == .settings ? .history : .settings
                    }
                    .keyboardShortcut(",")
                    .accessibilityIdentifier("color-picker.settings")
                    .padding(OnePlusMetrics.actionSpacing)
                }
            }
        }
        .frame(height: windowHeight)
        .background {
            Button("Search colors") { page = .history; focusSearch += 1 }.keyboardShortcut("f").hidden()
        }
        .alert("Could Not Export Project", isPresented: Binding(
            get: { service.exportError != nil }, set: { if !$0 { service.exportError = nil } }
        )) {
            Button("OK") { service.exportError = nil }
        } message: { Text(service.exportError ?? "The project could not be written.") }
        .onOpenToolPage("color-picker") { id in
            if let destination = ColorPickerPage(rawValue: id) { page = destination }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("color-picker") == true else { return }
            page = .settings
        }
    }

    private var tabBar: some View {
        OnePlusTabStrip(tabs: [OnePlusTab(.history, "History"), OnePlusTab(.projects, "Projects")],
                        selection: $page, layout: .applet) {
            Text(selectedProjectName).onePlusText(.caption).lineLimit(1).help(selectedProjectName)
        }
    }

    private var history: some View {
        VStack(spacing: OnePlusMetrics.contentTop) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusSearchField(prompt: "Search colors", text: $search, width: nil,
                                   focusTrigger: focusSearch, accessibilityIdentifier: "color-picker.search")
                OnePlusSelect(choices: ColorCopyFormat.allCases.map { ($0, $0.title) },
                              selection: $service.defaultFormat, width: OnePlusMetrics.controlColumn,
                              accessibilityLabel: "Copy format")
                    .accessibilityIdentifier("color-picker.format")
            }
            .padding(.horizontal, OnePlusMetrics.appletGutter)
            if samples.isEmpty {
                OnePlusEmptyState(search.isEmpty ? "Pick a color for \(selectedProjectName)" : "No matching colors",
                                  systemImage: search.isEmpty ? "eyedropper" : "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: OnePlusMetrics.actionSpacing) {
                        ForEach(samples) { ColorSampleRow(sample: $0) }
                    }
                    .padding(.horizontal, OnePlusMetrics.appletGutter)
                }.onePlusScrollIndicators()
            }
        }.padding(.top, OnePlusMetrics.contentTop)
    }

    private var projects: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                OnePlusCard {
                    OnePlusCardHeader("Color projects") {
                        Button("New Project", systemImage: "plus") { isCreatingProject.toggle() }
                            .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    }
                    if isCreatingProject { newProjectField }
                    LazyVStack(spacing: 0) {
                        projectRow(id: nil, name: "Unfiled", project: nil)
                        ForEach(service.projects) { project in
                            projectRow(id: project.id, name: project.name, project: project)
                        }
                    }
                }
            }
            .padding(.horizontal, OnePlusMetrics.appletGutter)
            .padding(.top, OnePlusMetrics.contentTop)
        }.onePlusScrollIndicators()
    }

    private var newProjectField: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusTextField("Project name", text: $newProjectName, onSubmit: createProject)
            Button("Create", action: createProject)
                .buttonStyle(OnePlusButtonStyle())
                .disabled(!service.canCreateProject(named: newProjectName))
            Button { isCreatingProject = false; newProjectName = "" } label: { Image(systemName: "xmark") }
                .buttonStyle(OnePlusButtonStyle(.icon)).help("Cancel").accessibilityLabel("Cancel new project")
        }.padding(OnePlusMetrics.cardPadding)
    }

    private func createProject() {
        guard service.createProject(named: newProjectName) != nil else { return }
        newProjectName = ""
        isCreatingProject = false
        page = .history
    }

    private func projectRow(id: UUID?, name: String, project: ColorProject?) -> some View {
        let count = service.samples(in: id).count
        let selected = service.selectedProjectID == id
        return HStack(spacing: OnePlusMetrics.actionSpacing) {
            Button { selectProject(id) } label: {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: "folder")
                    Text(name).lineLimit(1).help(name)
                    OnePlusBadge(count)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark") }
                }
                .onePlusText(.row)
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.settingRow)
                .contentShape(Rectangle())
            }.buttonStyle(OnePlusInteractionStyle(selected: selected))
            if let project {
                Button { service.export(project) } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .disabled(count == 0).help("Export \(name) as CSS").accessibilityLabel("Export \(name) as CSS")
            }
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .contextMenu {
            Button("Use project") { selectProject(id) }
            if let project { Button("Export CSS") { service.export(project) }.disabled(count == 0) }
        }
    }

    private func selectProject(_ id: UUID?) {
        service.selectProject(id)
        search = ""
        page = .history
    }
}

struct ColorPickerSettingsView: View {
    @State private var service = ColorPickerService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var isConfirmingClearAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Global shortcut", systemImage: "keyboard")
                OnePlusSettingRow("Enable shortcut") {
                    Toggle("Enable Pick Color shortcut", isOn: Binding(
                        get: { shortcuts.isEnabled(.colorPicker) }, set: { shortcuts.setEnabled($0, for: .colorPicker) }
                    )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Keyboard shortcut", caption: "Works in every app.", separator: false) {
                    ShortcutRecorderField(action: .colorPicker).disabled(!shortcuts.isEnabled(.colorPicker))
                }
                ShortcutPermissionNotice(action: .colorPicker)
            }
            OnePlusCard {
                OnePlusCardHeader("Saved colors")
                OnePlusSettingRow("Copy format") {
                    OnePlusSelect(choices: ColorCopyFormat.allCases.map { ($0, $0.title) },
                                  selection: $service.defaultFormat, accessibilityLabel: "Copy format")
                }
                OnePlusSettingRow("Clear history", caption: "Keeps your projects.", separator: false) {
                    Button("Clear All", role: .destructive) { isConfirmingClearAll = true }
                        .buttonStyle(OnePlusButtonStyle(.destructive))
                        .disabled(service.history.isEmpty).help("Clear every saved color")
                        .accessibilityIdentifier("color-picker.clear-all")
                }
            }
        }
        .confirmationDialog("Clear all picked colors?", isPresented: $isConfirmingClearAll) {
            Button("Clear All", role: .destructive) { service.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes every saved color from History and all projects. Projects are kept.") }
    }
}

private enum ColorPickerPage: String { case history, projects, settings }

private struct ColorSampleRow: View {
    private static let relativeDateStyle = Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .abbreviated)
    let sample: ColorSample
    @State private var service = ColorPickerService.shared
    @State private var hovering = false
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        OnePlusCard {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                    .fill(Color(nsColor: sample.color))
                    .frame(width: OnePlusMetrics.searchHeight, height: OnePlusMetrics.searchHeight)
                    .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius).strokeBorder(OnePlusColor.line) }
                    .accessibilityLabel(sample.string(.hex))
                HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                    Text(sample.string(service.defaultFormat)).onePlusText(.mono)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .help(sample.string(service.defaultFormat))
                    Spacer(minLength: 0)
                    Text(sample.createdAt.formatted(Self.relativeDateStyle)).onePlusText(.caption).fixedSize()
                }.frame(maxWidth: .infinity, alignment: .leading)
                actions
                    .opacity(hovering || focused || NSApp.isFullKeyboardAccessEnabled ? 1 : 0)
            }
            .padding(.horizontal, OnePlusMetrics.actionSpacing)
            .frame(height: ColorPickerLayout.historyRowHeight)
            .background(hovering || focused ? OnePlusColor.panelHover : OnePlusColor.panel)
        }
        .contentShape(Rectangle()).focusable().focused($focused)
        .onHover { hovering = $0 }
        .onKeyPress(.return) { service.copy(sample, as: service.defaultFormat); return .handled }
        .onKeyPress(.delete) { confirmingDelete = true; return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            guard let number = Int(press.characters), ColorCopyFormat.allCases.indices.contains(number - 1) else { return .ignored }
            service.copy(sample, as: ColorCopyFormat.allCases[number - 1])
            return .handled
        }
        .contextMenu {
            ForEach(ColorCopyFormat.allCases) { format in
                Button("Copy \(format.title)") { service.copy(sample, as: format) }
            }
            Button(sample.isPinned ? "Unpin" : "Pin") { service.togglePin(sample.id) }
            Button("Delete", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete this color?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { service.remove(sample.id) }
        }
    }

    private var actions: some View {
        HStack(spacing: OnePlusMetrics.spacing[0]) {
            Menu {
                ForEach(ColorCopyFormat.allCases) { format in
                    Button(format.title) { service.copy(sample, as: format) }
                }
            } label: {
                OnePlusControlLabel(variant: .icon, size: .small) { Image(systemName: "doc.on.doc") }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("Copy as").accessibilityLabel("Copy color as")
            Button { service.togglePin(sample.id) } label: { Image(systemName: sample.isPinned ? "pin.fill" : "pin") }
                .help(sample.isPinned ? "Unpin" : "Pin").accessibilityLabel(sample.isPinned ? "Unpin color" : "Pin color")
            Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                .help("Delete").accessibilityLabel("Delete color")
        }.buttonStyle(OnePlusButtonStyle(.icon, size: .small))
    }
}

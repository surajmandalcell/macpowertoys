import SwiftUI
import OnePlusUI

enum ColorPickerLayout {
    static let windowWidth = OnePlusWindowCanvas.colorPicker.size.width
    static let bodyHorizontalInset = OnePlusMetrics.appletGutter
    static let historyBaseHeight = OnePlusWindowCanvas.colorPicker.size.height - OnePlusMetrics.appletTitlebar
    static let maximumWindowHeight = OnePlusWindowCanvas.colorPicker.heightRange!.upperBound
    static let settingsContentHeight = 2 * OnePlusMetrics.cardHeader
        + 4 * OnePlusMetrics.settingRow
        + OnePlusMetrics.cardGap
    static let historyRowHeight = OnePlusMetrics.settingRow

    static func historyHeight(count: Int) -> CGFloat {
        min(maximumWindowHeight, historyBaseHeight + OnePlusMetrics.appletTitlebar
            + CGFloat(max(0, min(count, 5) - 1)) * historyRowHeight)
    }

    static func settingsHeight(contentHeight: CGFloat) -> CGFloat {
        let range = OnePlusWindowCanvas.colorPicker.heightRange!
        return min(range.upperBound, max(range.lowerBound, contentHeight
            + OnePlusMetrics.appletTitlebar + OnePlusMetrics.contentGap
            + OnePlusMetrics.floatingSettingsInset))
    }

    static func projectsHeight(projectCount: Int, isCreating: Bool) -> CGFloat {
        min(maximumWindowHeight, OnePlusWindowCanvas.colorPicker.size.height
            + CGFloat(max(0, projectCount)) * OnePlusMetrics.settingRow
            + (isCreating ? OnePlusMetrics.controlHeight + OnePlusMetrics.contentGap : 0))
    }
}

nonisolated struct ColorPickerHistoryRequest: Hashable, Sendable {
    struct Revision: Hashable, Sendable {
        let id: UUID
        let projectID: UUID?
        let isPinned: Bool
    }

    let revisions: [Revision]
    let projectID: UUID?
    let search: String
    let format: ColorCopyFormat
}

nonisolated struct ColorSamplePresentation: Identifiable, Sendable {
    let sample: ColorSample
    let value: String
    let accessibilityValue: String
    let timestamp: String
    var id: UUID { sample.id }
}

nonisolated struct ColorPickerPresentation: Sendable {
    let samples: [ColorSamplePresentation]
    let projectCounts: [UUID: Int]
    let unfiledCount: Int
}

nonisolated func colorPickerPresentation(
    history: [ColorSample], projectID: UUID?, search: String,
    format: ColorCopyFormat, now: Date = Date()
) -> ColorPickerPresentation {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let dateFormatter = RelativeDateTimeFormatter()
    dateFormatter.dateTimeStyle = .numeric
    dateFormatter.unitsStyle = .abbreviated
    let samples = history.lazy.filter { sample in
        guard sample.projectID == projectID else { return false }
        return query.isEmpty || ColorCopyFormat.allCases.contains {
            sample.string($0).localizedCaseInsensitiveContains(query)
        }
    }.map {
        ColorSamplePresentation(
            sample: $0,
            value: $0.string(format),
            accessibilityValue: $0.string(.hex),
            timestamp: dateFormatter.localizedString(for: $0.createdAt, relativeTo: now)
        )
    }
    return ColorPickerPresentation(
        samples: Array(samples),
        projectCounts: Dictionary(grouping: history.compactMap { sample in
            sample.projectID.map { ($0, sample.id) }
        }, by: \.0).mapValues(\.count),
        unfiledCount: history.lazy.filter { $0.projectID == nil }.count
    )
}

struct ColorHistoryView: View {
    @State private var service = ColorPickerService.shared
    @State private var page = ColorPickerPage.history
    @State private var search = ""
    @State private var focusSearch = 0
    @State private var settingsContentHeight = ColorPickerLayout.settingsContentHeight
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var sampleRows: [ColorSamplePresentation] = []
    @State private var projectCounts: [UUID: Int] = [:]
    @State private var unfiledCount = 0

    private var historyRequest: ColorPickerHistoryRequest {
        ColorPickerHistoryRequest(
            revisions: service.history.map { .init(id: $0.id, projectID: $0.projectID, isPinned: $0.isPinned) },
            projectID: service.selectedProjectID,
            search: search,
            format: service.defaultFormat
        )
    }

    private var selectedProjectName: String {
        service.projects.first { $0.id == service.selectedProjectID }?.name ?? "Unfiled"
    }

    private var windowHeight: CGFloat {
        switch page {
        case .history: ColorPickerLayout.historyHeight(count: sampleRows.count)
        case .projects: ColorPickerLayout.projectsHeight(
            projectCount: service.projects.count,
            isCreating: isCreatingProject
        )
        case .settings: ColorPickerLayout.settingsHeight(contentHeight: settingsContentHeight)
        }
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .colorPicker, sidebar: { EmptyView() }) {
            VStack(spacing: 0) {
                OnePlusAppletTitlebar(title: "Color Picker") {
                    Button("Pick Color") { service.pick() }
                        .buttonStyle(OnePlusButtonStyle(.primary, size: .small))
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
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    settingsContentHeight = $0
                                }
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
        .transaction { $0.disablesAnimations = true }
        .onOpenToolPage("color-picker") { id in
            if let destination = ColorPickerPage(rawValue: id) { page = destination }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("color-picker") == true else { return }
            page = .settings
        }
        .task(id: historyRequest) {
            let request = historyRequest
            let history = service.history
            let task = Task.detached(priority: .userInitiated) {
                colorPickerPresentation(
                    history: history, projectID: request.projectID,
                    search: request.search, format: request.format
                )
            }
            let presentation = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled, historyRequest == request else { return }
            sampleRows = presentation.samples
            projectCounts = presentation.projectCounts
            unfiledCount = presentation.unfiledCount
        }
    }

    private var tabBar: some View {
        OnePlusTabStrip(tabs: [OnePlusTab(.history, "History"), OnePlusTab(.projects, "Projects")],
                        selection: $page, layout: .applet) {
            Text(selectedProjectName).onePlusText(.caption).lineLimit(1).help(selectedProjectName)
        }
    }

    private var history: some View {
        VStack(spacing: OnePlusMetrics.contentGap) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusSearchField(prompt: "Search colors", text: $search, width: nil,
                                   focusTrigger: focusSearch, accessibilityIdentifier: "color-picker.search")
                OnePlusSelect(choices: ColorCopyFormat.allCases.map { ($0, $0.title) },
                              selection: $service.defaultFormat, width: OnePlusMetrics.controlColumn,
                              accessibilityLabel: "Copy format")
                    .accessibilityIdentifier("color-picker.format")
            }
            .padding(.horizontal, OnePlusMetrics.appletGutter)
            if sampleRows.isEmpty {
                OnePlusEmptyState(search.isEmpty ? "Pick a color for \(selectedProjectName)" : "No matching colors",
                                  systemImage: search.isEmpty ? "eyedropper" : "magnifyingglass")
            } else {
                OnePlusCard {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sampleRows) { row in
                                ColorSampleRow(
                                    row: row,
                                    defaultFormat: service.defaultFormat,
                                    copy: service.copy,
                                    togglePin: service.togglePin,
                                    remove: service.remove
                                )
                                .overlay(alignment: .bottom) {
                                    if row.id != sampleRows.last?.id {
                                        OnePlusColor.lineSoft.frame(height: 1)
                                    }
                                }
                            }
                        }
                    }
                    .onePlusScrollIndicators()
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, OnePlusMetrics.appletGutter)
            }
        }.padding(.top, OnePlusMetrics.contentGap)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusSectionTitle("Color projects")
                Button("New Project", systemImage: "plus") { isCreatingProject.toggle() }
                    .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
            }
            if isCreatingProject { newProjectField }
            ScrollView {
                LazyVStack(spacing: 0) {
                    projectRow(id: nil, name: "Unfiled", project: nil)
                    ForEach(service.projects) { project in
                        projectRow(id: project.id, name: project.name, project: project)
                    }
                }
            }
            .onePlusScrollIndicators()
            .frame(maxHeight: CGFloat(service.projects.count + 1) * OnePlusMetrics.settingRow)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, OnePlusMetrics.appletGutter)
        .padding(.top, OnePlusMetrics.contentGap)
    }

    private var newProjectField: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusTextField("Project name", text: $newProjectName, onSubmit: createProject)
            Button("Create", action: createProject)
                .buttonStyle(OnePlusButtonStyle())
                .disabled(!service.canCreateProject(named: newProjectName))
            Button { isCreatingProject = false; newProjectName = "" } label: { Image(systemName: "xmark") }
                .buttonStyle(OnePlusButtonStyle(.icon)).help("Cancel").accessibilityLabel("Cancel new project")
        }
    }

    private func createProject() {
        guard service.createProject(named: newProjectName) != nil else { return }
        newProjectName = ""
        isCreatingProject = false
        page = .history
    }

    private func projectRow(id: UUID?, name: String, project: ColorProject?) -> some View {
        let count = id.map { projectCounts[$0, default: 0] } ?? unfiledCount
        let selected = service.selectedProjectID == id
        return HStack(spacing: OnePlusMetrics.actionSpacing) {
            Button { selectProject(id) } label: {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: "folder")
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(count, format: .number).onePlusText(.caption).monospacedDigit().fixedSize()
                        .accessibilityLabel("\(count) saved colors")
                    if selected { Image(systemName: "checkmark") }
                }
                .onePlusText(.row)
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.settingRow)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let project {
                Button { service.export(project, from: NSApp.windows.first { $0.identifier?.rawValue == "color-picker" }) } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .disabled(count == 0).accessibilityLabel("Export \(name) as CSS")
            }
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .onePlusRowHover(selected: selected)
        .contextMenu {
            Button("Use project") { selectProject(id) }
            if let project { Button("Export CSS") { service.export(project, from: NSApp.windows.first { $0.identifier?.rawValue == "color-picker" }) }.disabled(count == 0) }
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                    shortcutSettings
                    savedColorsSettings
                }
                .frame(minWidth: 2 * OnePlusWindowCanvas.colorPicker.size.width + OnePlusMetrics.cardGap)
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    shortcutSettings
                    savedColorsSettings
                }
            }
        }
        .transaction { $0.disablesAnimations = true }
        .confirmationDialog("Clear all picked colors?", isPresented: $isConfirmingClearAll) {
            Button("Clear all", role: .destructive) { service.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes every saved color from History and all projects. Projects are kept.") }
    }

    private var shortcutSettings: some View {
        OnePlusCard {
            OnePlusCardHeader("Global shortcut", systemImage: "keyboard")
            OnePlusSettingRow("Enable shortcut") {
                Toggle("Enable Pick Color shortcut", isOn: Binding(
                    get: { shortcuts.isEnabled(.colorPicker) }, set: { shortcuts.setEnabled($0, for: .colorPicker) }
                )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Keyboard shortcut", help: "Works in every app.", separator: false) {
                ShortcutRecorderField(action: .colorPicker).disabled(!shortcuts.isEnabled(.colorPicker))
            }
            ShortcutPermissionNotice(action: .colorPicker)
        }
    }

    private var savedColorsSettings: some View {
        OnePlusCard {
            OnePlusCardHeader("Saved colors", systemImage: "paintpalette")
            OnePlusSettingRow("Copy format") {
                OnePlusSelect(choices: ColorCopyFormat.allCases.map { ($0, $0.title) },
                              selection: $service.defaultFormat, accessibilityLabel: "Copy format")
            }
            OnePlusSettingRow("Clear history", help: "Keeps your projects.", separator: false) {
                Button("Clear all", role: .destructive) { isConfirmingClearAll = true }
                    .buttonStyle(OnePlusButtonStyle(.destructive))
                    .disabled(service.history.isEmpty).help("Clear every saved color")
                    .accessibilityIdentifier("color-picker.clear-all")
            }
        }
    }
}

private enum ColorPickerPage: String { case history, projects, settings }

private struct ColorSampleRow: View {
    let row: ColorSamplePresentation
    let defaultFormat: ColorCopyFormat
    let copy: (ColorSample, ColorCopyFormat) -> Void
    let togglePin: (UUID) -> Void
    let remove: (UUID) -> Void
    @State private var hovering = false
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        let sample = row.sample
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius)
                .fill(Color(nsColor: sample.color))
                .frame(width: OnePlusMetrics.searchHeight, height: OnePlusMetrics.searchHeight)
                .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius).strokeBorder(OnePlusColor.line) }
                .accessibilityLabel(row.accessibilityValue)
            HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                Text(row.value).onePlusText(.mono)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 0)
                Text(row.timestamp).onePlusText(.caption).fixedSize()
            }.frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, OnePlusMetrics.actionSpacing)
        .frame(height: ColorPickerLayout.historyRowHeight)
        .background(hovering || (focused && OnePlusFocusPolicy.shared.showsFocus) ? OnePlusColor.panelHover : OnePlusColor.panel)
        .contentShape(Rectangle()).focusable().focused($focused)
        .onHover { hovering = $0 }
        .onKeyPress(.return) { copy(sample, defaultFormat); return .handled }
        .onKeyPress(.delete) { confirmingDelete = true; return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            guard let number = Int(press.characters), ColorCopyFormat.allCases.indices.contains(number - 1) else { return .ignored }
            copy(sample, ColorCopyFormat.allCases[number - 1])
            return .handled
        }
        .contextMenu {
            ForEach(ColorCopyFormat.allCases) { format in
                Button("Copy \(format.title)") { copy(sample, format) }
            }
            Button(sample.isPinned ? "Unpin" : "Pin") { togglePin(sample.id) }
            Button("Delete", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete this color?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { remove(sample.id) }
        }
    }

    private var actions: some View {
        HStack(spacing: OnePlusMetrics.spacing[0]) {
            OnePlusMenuButton("Copy color as", systemImage: "doc.on.doc", variant: .borderedIcon) {
                ColorCopyFormat.allCases.map { format in
                    .item(OnePlusPopupMenuItem(format.title) { copy(row.sample, format) })
                }
            }
            .environment(\.onePlusDensity, .compact)
            Button { togglePin(row.id) } label: { Image(systemName: row.sample.isPinned ? "pin.fill" : "pin") }
                .accessibilityLabel(row.sample.isPinned ? "Unpin color" : "Pin color")
            Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                .accessibilityLabel("Delete color")
        }.buttonStyle(OnePlusButtonStyle(.icon, size: .small))
    }
}

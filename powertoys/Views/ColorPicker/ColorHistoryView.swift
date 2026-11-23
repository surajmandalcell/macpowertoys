import SwiftUI
import OnePlusUI

enum ColorPickerLayout {
    static let windowWidth = OnePlusWindowCanvas.colorPicker.size.width
    static let bodyHorizontalInset = OnePlusMetrics.appletGutter
    static let historyBaseHeight = OnePlusWindowCanvas.colorPicker.size.height - OnePlusMetrics.appletTitlebar
    static let maximumWindowHeight = OnePlusWindowCanvas.colorPicker.heightRange!.upperBound
    static let historyRowHeight = OnePlusLinearMetrics.appletRow
    static let formatSelectWidth: CGFloat = 92
    /// Title area, tab row, and the toolbar (field plus its gaps) above the rows; the bottom gutter below them.
    static let historyChrome = OnePlusLinearMetrics.appletTitlebar + OnePlusLinearMetrics.appletTabStrip
        + 2 * OnePlusLinearMetrics.appletToolbarGap + OnePlusLinearMetrics.appletField + OnePlusLinearMetrics.appletBottom

    static func clamped(_ height: CGFloat) -> CGFloat {
        let range = OnePlusWindowCanvas.colorPicker.heightRange!
        return min(range.upperBound, max(range.lowerBound, height))
    }

    static func historyHeight(count: Int) -> CGFloat {
        clamped(historyChrome + CGFloat(max(0, count)) * historyRowHeight)
    }

    static func projectsHeight(projectCount: Int, isCreating: Bool) -> CGFloat {
        let toolbar = 2 * OnePlusLinearMetrics.appletToolbarGap
            + (isCreating ? OnePlusLinearMetrics.appletField : OnePlusLinearMetrics.appletButton)
        return clamped(OnePlusLinearMetrics.appletTitlebar + OnePlusLinearMetrics.appletTabStrip + toolbar
            + CGFloat(max(0, projectCount) + 1) * historyRowHeight + OnePlusLinearMetrics.appletBottom)
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
            timestamp: abs($0.createdAt.timeIntervalSince(now)) < 60
                ? "Just now" : dateFormatter.localizedString(for: $0.createdAt, relativeTo: now)
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
    @Environment(\.undoManager) private var undoManager
    @State private var service: ColorPickerService
    @State private var page: ColorPickerPage
    @State private var search = ""
    @State private var focusSearch = 0
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var sampleRows: [ColorSamplePresentation] = []
    @State private var projectCounts: [UUID: Int] = [:]
    @State private var unfiledCount = 0

    init(service: ColorPickerService = .shared, page: ColorPickerPage = .history) {
        _service = State(initialValue: service)
        _page = State(initialValue: page)
    }

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
        }
    }

    var body: some View {
        OnePlusLinearApplet("Color Picker", canvas: .colorPicker) {
            OnePlusLinearAppletSettingsButton(isActive: false) {
                ToolActionRouter.shared.openMainPage(toolID: "color-picker")
            }
            .accessibilityIdentifier("color-picker.settings")
            Button { service.pick() } label: { Label("Pick Color", systemImage: "eyedropper") }
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
                .disabled(service.isPicking)
                .help("Pick a color for \(selectedProjectName)")
                .accessibilityIdentifier("color-picker.pick")
        } content: {
            VStack(spacing: 0) {
                tabBar
                OnePlusLinearContentSwitch(page) {
                    switch page {
                    case .history: history
                    case .projects: projects
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .onePlusLinearMotion(.quiet)
        .onePlusNeutralControls()
        .frame(height: windowHeight)
        .background {
            // On History the applet search field owns Command-F; elsewhere it opens History and focuses search.
            if page != .history {
                Button("Search colors") { page = .history; focusSearch += 1 }.keyboardShortcut("f").hidden()
            }
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
            ToolActionRouter.shared.openMainPage(toolID: "color-picker")
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
        OnePlusLinearAppletTabRow(tabs: [OnePlusTab(.history, "History", count: sampleRows.count),
                                         OnePlusTab(.projects, "Projects", count: service.projects.count)],
                                  selection: $page) {
            OnePlusLinearSelect(choices: [(UUID?.none, "Unfiled")] + service.projects.map { (Optional($0.id), $0.name) },
                                selection: Binding(get: { service.selectedProjectID }, set: { selectProject($0) }),
                                accessibilityLabel: "Project", style: .text)
                .help(selectedProjectName)
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            OnePlusLinearAppletToolbar {
                OnePlusLinearSearchField("Search colors", text: $search, accessibilityIdentifier: "color-picker.search",
                                         focusTrigger: focusSearch, style: .applet)
                OnePlusLinearSelect(choices: ColorCopyFormat.allCases.map { ($0, $0.title) },
                                    selection: $service.defaultFormat, accessibilityLabel: "Copy format",
                                    width: ColorPickerLayout.formatSelectWidth)
                    .accessibilityIdentifier("color-picker.format")
            }
            if sampleRows.isEmpty {
                OnePlusLinearEmptyState(search.isEmpty ? "Pick a color for \(selectedProjectName)" : "No matching colors",
                                        systemImage: search.isEmpty ? "eyedropper" : "magnifyingglass")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    OnePlusLinearAppletGroup {
                        ForEach(sampleRows) { row in
                            ColorSampleRow(
                                row: row,
                                defaultFormat: service.defaultFormat,
                                copy: service.copy,
                                togglePin: { service.togglePin($0, undoManager: undoManager) },
                                remove: { service.remove($0, undoManager: undoManager) }
                            )
                        }
                    }
                    .padding(.horizontal, OnePlusLinearMetrics.appletGutter)
                    .padding(.bottom, OnePlusLinearMetrics.appletBottom)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onePlusScrollIndicators()
            }
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusLinearAppletToolbar {
                if isCreatingProject {
                    newProjectField
                } else {
                    Button { isCreatingProject = true } label: { Label("New Project", systemImage: "plus") }
                        .buttonStyle(OnePlusLinearButtonStyle(.soft))
                    Spacer(minLength: 0)
                }
            }
            ScrollView {
                OnePlusLinearAppletGroup {
                    projectRow(id: nil, name: "Unfiled", project: nil)
                    ForEach(service.projects) { project in
                        projectRow(id: project.id, name: project.name, project: project)
                    }
                }
                .padding(.horizontal, OnePlusLinearMetrics.appletGutter)
                .padding(.bottom, OnePlusLinearMetrics.appletBottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onePlusScrollIndicators()
        }
    }

    @ViewBuilder private var newProjectField: some View {
        OnePlusLinearTextField("Project name", text: $newProjectName, onSubmit: createProject)
            .environment(\.onePlusLinearControlLook, .quietRaisedActionRow)
        Button("Create", action: createProject)
            .buttonStyle(OnePlusLinearButtonStyle(.soft))
            .disabled(!service.canCreateProject(named: newProjectName))
        OnePlusLinearIconButton(systemImage: "xmark", help: "Cancel new project", size: OnePlusLinearMetrics.appletButton) {
            isCreatingProject = false; newProjectName = ""
        }
    }

    private func createProject() {
        guard service.createProject(named: newProjectName, undoManager: undoManager) != nil else { return }
        newProjectName = ""
        isCreatingProject = false
        page = .history
    }

    private func projectRow(id: UUID?, name: String, project: ColorProject?) -> some View {
        let count = id.map { projectCounts[$0, default: 0] } ?? unfiledCount
        let selected = service.selectedProjectID == id
        var actions: [OnePlusLinearAction] = []
        if let project, count > 0 {
            actions.append(OnePlusLinearAction("Export \(name) as CSS", systemImage: "square.and.arrow.up", id: "export",
                                               action: { exportProject(project) }))
        }
        return OnePlusLinearAppletListRow(name, metadata: count.formatted(), actions: actions) {
            Image(systemName: selected ? "checkmark" : "folder")
                .font(.system(size: OnePlusLinearMetrics.body))
                .foregroundStyle(selected ? OnePlusLinearColor.ink : OnePlusLinearColor.appletSecondary)
                .frame(width: OnePlusLinearMetrics.appletSwatch)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectProject(id) }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selectProject(id) }
        .accessibilityValue("\(count) saved colors")
        .contextMenu {
            Button("Use project") { selectProject(id) }
            if let project { Button("Export CSS") { exportProject(project) }.disabled(count == 0) }
        }
    }

    private func exportProject(_ project: ColorProject) {
        service.export(project, from: NSApp.windows.first { $0.identifier?.rawValue == "color-picker" })
    }

    private func selectProject(_ id: UUID?) {
        service.selectProject(id, undoManager: undoManager)
        search = ""
        page = .history
    }
}

struct ColorPickerSettingsView: View {
    @Environment(\.undoManager) private var undoManager
    @State private var service = ColorPickerService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var isConfirmingClearAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
                OnePlusLinearAppletSection("Global shortcut") {
                    OnePlusLinearAppletRow("Enable shortcut", systemImage: "power") {
                        Toggle("Enable Pick Color shortcut", isOn: Binding(
                            get: { shortcuts.isEnabled(.colorPicker) }, set: { shortcuts.setEnabled($0, for: .colorPicker) }
                        )).toggleStyle(OnePlusLinearSwitchStyle())
                    }
                    OnePlusLinearAppletRow("Keyboard shortcut", detail: "Works in every app.", systemImage: "keyboard") {
                        ShortcutRecorderField(action: .colorPicker).disabled(!shortcuts.isEnabled(.colorPicker))
                    }
                }
                ShortcutPermissionNotice(action: .colorPicker)
                    .padding(.horizontal, OnePlusLinearMetrics.appletRowPadding)
                OnePlusLinearAppletSection("Saved colors") {
                    OnePlusLinearAppletRow("Copy format", systemImage: "doc.on.doc") {
                        OnePlusLinearSelect(choices: ColorCopyFormat.allCases.map { ($0, $0.title) },
                                            selection: $service.defaultFormat, accessibilityLabel: "Copy format",
                                            width: ColorPickerLayout.formatSelectWidth)
                    }
                }
            }
            Button("Clear All Saved Colors", role: .destructive) { isConfirmingClearAll = true }
                .buttonStyle(OnePlusLinearButtonStyle(.resetBlock))
                .disabled(service.history.isEmpty).help("Clear every saved color. Projects are kept.")
                .accessibilityIdentifier("color-picker.clear-all")
                .padding(.top, OnePlusLinearMetrics.appletFooterGap)
        }
        .transformEnvironment(\.onePlusLinearControlLook) { if $0 == nil { $0 = .quietRaised } }
        .confirmationDialog("Clear all picked colors?", isPresented: $isConfirmingClearAll) {
            Button("Clear all", role: .destructive) { service.clearAll(undoManager: undoManager) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes every saved color from History and all projects. Projects are kept.") }
    }
}

enum ColorPickerPage: String { case history, projects }

private struct ColorSampleRow: View {
    let row: ColorSamplePresentation
    let defaultFormat: ColorCopyFormat
    let copy: (ColorSample, ColorCopyFormat) -> Void
    let togglePin: (UUID) -> Void
    let remove: (UUID) -> Void
    @State private var confirmingDelete = false
    @State private var hovering = false

    // shortcut: built from applet tokens because OnePlusLinearAppletListRow 1.2.1 takes a plain String title and
    // fixed icon actions (no selectable value, no menu action); move back to it when OnePlusUI adds both.
    var body: some View {
        let sample = row.sample
        HStack(spacing: 0) {
            OnePlusLinearSwatch(Color(nsColor: sample.color))
                .padding(.trailing, OnePlusLinearMetrics.appletRowGap)
            Text(row.value)
                .font(.system(size: OnePlusLinearMetrics.body, design: .monospaced))
                .foregroundStyle(OnePlusLinearColor.ink)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.timestamp)
                .linearText(color: OnePlusLinearColor.appletMuted)
                .lineLimit(1).fixedSize()
                .padding(.leading, OnePlusLinearMetrics.appletRowGap)
            HStack(spacing: 2) {
                OnePlusLinearIconButton(systemImage: "doc.on.doc", help: "Copy \(defaultFormat.title)",
                                        size: OnePlusLinearMetrics.appletRowAction) { copy(sample, defaultFormat) }
                OnePlusMenuButton("Copy color as", systemImage: "chevron.down", variant: .borderedIcon) {
                    ColorCopyFormat.allCases.map { format in
                        .item(OnePlusPopupMenuItem(format.title) { copy(sample, format) })
                    }
                }
                .environment(\.onePlusDensity, .compact)
                OnePlusLinearIconButton(systemImage: sample.isPinned ? "pin.fill" : "pin",
                                        help: sample.isPinned ? "Unpin color" : "Pin color",
                                        size: OnePlusLinearMetrics.appletRowAction) { togglePin(sample.id) }
                OnePlusLinearIconButton(systemImage: "trash", help: "Delete color",
                                        size: OnePlusLinearMetrics.appletRowAction) { confirmingDelete = true }
            }
            .padding(.leading, OnePlusLinearMetrics.appletRowActionsGap)
        }
        .padding(.leading, OnePlusLinearMetrics.appletRowPadding)
        .padding(.trailing, OnePlusLinearMetrics.appletRowActionsTrailing)
        .frame(height: OnePlusLinearMetrics.appletRow)
        .background(hovering ? OnePlusLinearColor.hover : .clear)
        .contentShape(Rectangle())
        .onePlusHover($hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityValue)
        .focusable()
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
}

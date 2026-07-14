import SwiftUI

enum ColorPickerLayout {
    static let windowWidth: CGFloat = 420
    static let historyBaseHeight: CGFloat = 210
    static let maximumWindowHeight: CGFloat = 420
    static let settingsHeight: CGFloat = 280
    static let maximumVisibleSamples = 5
    static let historyRowHeight: CGFloat = 56
    static let projectsBaseHeight: CGFloat = 230
    static let maximumVisibleProjects = 4
    static let projectRowHeight: CGFloat = 48
    static let newProjectHeight: CGFloat = 40
}

struct ColorHistoryView: View {
    @State private var service = ColorPickerService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var page = ColorPickerPage.history
    @State private var search = ""
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @FocusState private var isProjectNameFocused: Bool

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
        case .history:
            ColorPickerLayout.historyBaseHeight
                + CGFloat(max(0, min(samples.count, ColorPickerLayout.maximumVisibleSamples) - 1))
                * ColorPickerLayout.historyRowHeight
        case .projects:
            min(
                ColorPickerLayout.maximumWindowHeight,
                ColorPickerLayout.projectsBaseHeight
                    + CGFloat(min(service.projects.count, ColorPickerLayout.maximumVisibleProjects))
                    * ColorPickerLayout.projectRowHeight
                    + (isCreatingProject ? ColorPickerLayout.newProjectHeight : 0)
            )
        case .settings: ColorPickerLayout.settingsHeight
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            tabBar
            Divider()
            switch page {
            case .history: history
            case .projects: projects
            case .settings: settings
            }
        }
        .frame(
            width: ColorPickerLayout.windowWidth,
            height: windowHeight + UtilityLayout.compactTitlebarHeight
        )
        .ignoresSafeArea(.container, edges: .top)
        .utilityWindowBackground()
        .animation(.easeInOut(duration: 0.16), value: windowHeight)
        .alert("Couldn’t Export Project", isPresented: Binding(
            get: { service.exportError != nil },
            set: { if !$0 { service.exportError = nil } }
        )) {
            Button("OK") { service.exportError = nil }
        } message: {
            Text(service.exportError ?? "The project could not be written.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("color-picker") == true else { return }
            page = .settings
        }
    }

    private var titlebar: some View {
        CompactTitlebar {
            CompactTitlebarTitle(title: "Color Picker")
        } actions: {
            HStack(spacing: 8) {
                if page == .history && !samples.isEmpty {
                    Button("Clear", role: .destructive) {
                        service.clearUnpinned(in: service.selectedProjectID)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .help("Clear unpinned colors in \(selectedProjectName)")
                    .accessibilityIdentifier("color-picker.clear")
                }
                CompactTitlebarButton(title: "Pick Color", isPrimary: true) { service.pick() }
                    .disabled(service.isPicking)
                    .help("Pick a color for \(selectedProjectName)")
                    .accessibilityIdentifier("color-picker.pick")
                CompactTitlebarIconButton(
                    systemName: "gearshape",
                    help: page == .settings ? "Close Settings" : "Settings"
                ) {
                    page = page == .settings ? .history : .settings
                }
                .accessibilityIdentifier("color-picker.settings")
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton("History", icon: "clock", page: .history)
            tabButton("Projects", icon: "folder", page: .projects)
            Spacer()
            Text(page == .settings ? "Settings" : selectedProjectName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .frame(height: 36)
    }

    private func tabButton(_ title: String, icon: String, page target: ColorPickerPage) -> some View {
        Button {
            page = target
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(page == target ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var history: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ColorSearchField(text: $search)
                ColorFormatSelect(selection: $service.defaultFormat)
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.vertical, 10)

            if samples.isEmpty {
                EmptyStateView(
                    icon: search.isEmpty ? "eyedropper" : "magnifyingglass",
                    message: search.isEmpty ? "Pick a color for \(selectedProjectName)" : "No matching colors"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(samples) { sample in
                            ColorSampleRow(sample: sample)
                        }
                    }
                    .padding(.horizontal, UtilityLayout.horizontalInset)
                    .padding(.bottom, UtilityLayout.contentBottomInset)
                }
                .thinScrollIndicators()
            }
        }
    }

    private var projects: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COLOR PROJECTS").utilitySectionHeader()
                Spacer()
                Button {
                    isCreatingProject.toggle()
                    if isCreatingProject {
                        Task { isProjectNameFocused = true }
                    }
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .contentShape(Rectangle())
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.vertical, 10)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    if isCreatingProject { newProjectField }
                    projectRow(id: nil, name: "Unfiled", project: nil)
                    ForEach(service.projects) { project in
                        projectRow(id: project.id, name: project.name, project: project)
                    }
                }
                .padding(.horizontal, UtilityLayout.horizontalInset)
                .padding(.bottom, UtilityLayout.contentBottomInset)
            }
            .thinScrollIndicators()
        }
    }

    private var newProjectField: some View {
        HStack(spacing: 8) {
            TextField("Project name", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isProjectNameFocused)
                .onSubmit(createProject)
            Button("Create", action: createProject)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canCreateProject)
            ColorPickerIconButton(systemName: "xmark", help: "Cancel") {
                isCreatingProject = false
                newProjectName = ""
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var canCreateProject: Bool {
        service.canCreateProject(named: newProjectName)
    }

    private func createProject() {
        guard service.createProject(named: newProjectName) != nil else { return }
        newProjectName = ""
        isCreatingProject = false
        page = .history
    }

    private func projectRow(id: UUID?, name: String, project: ColorProject?) -> some View {
        let count = service.samples(in: id).count
        let isSelected = service.selectedProjectID == id
        return HStack(spacing: 0) {
            Button {
                service.selectProject(id)
                search = ""
                page = .history
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(count) \(count == 1 ? "color" : "colors")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if let project {
                ColorPickerIconButton(systemName: "square.and.arrow.up", help: "Export \(name) as CSS") {
                    service.export(project)
                }
                .disabled(count == 0)
                .padding(.trailing, 7)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var settings: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GLOBAL SHORTCUT").utilitySectionHeader()
                VStack(spacing: 0) {
                    Toggle("Enable Pick Color shortcut", isOn: Binding(
                        get: { shortcuts.isEnabled(.colorPicker) },
                        set: { shortcuts.setEnabled($0, for: .colorPicker) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.bottom, 12)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keyboard shortcut")
                            .font(.system(size: 12, weight: .medium))
                        HStack {
                            Text("Modifiers")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Control + Option + Command")
                        }
                        Picker("Key", selection: Binding(
                            get: { shortcuts.key(for: .colorPicker) },
                            set: { shortcuts.setKey($0, for: .colorPicker) }
                        )) {
                            ForEach(GlobalShortcutKey.allCases) { key in
                                Text(key.title).tag(key)
                            }
                        }
                        .disabled(!shortcuts.isEnabled(.colorPicker))
                        Text("Works anywhere while MacPowerToys is running")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    .padding(.top, 12)
                }
                .padding(14)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.bottom, UtilityLayout.contentBottomInset)
        }
        .thinScrollIndicators()
    }
}

private enum ColorPickerPage {
    case history, projects, settings
}

private struct ColorPickerIconButton: View {
    let systemName: String
    let helpText: String
    let action: () -> Void
    @State private var isHovering = false

    init(systemName: String, help: String, action: @escaping () -> Void) {
        self.systemName = systemName
        helpText = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(helpText)
    }
}

private struct ColorSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search colors", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                ColorPickerIconButton(systemName: "xmark.circle.fill", help: "Clear search") { text = "" }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("color-picker.search")
    }
}

private struct ColorFormatSelect: View {
    @Binding var selection: ColorCopyFormat

    var body: some View {
        Menu {
            ForEach(ColorCopyFormat.allCases) { format in
                Button(format.title) { selection = format }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.title).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .frame(width: 112, height: 28)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .help("Copy format")
        .accessibilityIdentifier("color-picker.format")
    }
}

private struct ColorSampleRow: View {
    private static let relativeDateStyle = Date.RelativeFormatStyle(
        presentation: .numeric,
        unitsStyle: .abbreviated
    )

    let sample: ColorSample
    @State private var service = ColorPickerService.shared
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: sample.color))
                .frame(width: 32, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.string(service.defaultFormat))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(sample.createdAt.formatted(Self.relativeDateStyle))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(ColorCopyFormat.allCases) { format in
                    Button(format.title) { service.copy(sample, as: format) }
                }
            } label: {
                Image(systemName: "doc.on.doc").frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .contentShape(Rectangle())
            .help("Copy as")
            Button { service.togglePin(sample.id) } label: {
                Image(systemName: sample.isPinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
            }
            .contentShape(Rectangle())
            .help(sample.isPinned ? "Unpin" : "Pin")
            Button(role: .destructive) { service.remove(sample.id) } label: {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
            .contentShape(Rectangle())
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(9)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .onKeyPress(.return) {
            service.copy(sample, as: service.defaultFormat)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            guard let number = Int(press.characters),
                  ColorCopyFormat.allCases.indices.contains(number - 1)
            else { return .ignored }
            service.copy(sample, as: ColorCopyFormat.allCases[number - 1])
            return .handled
        }
    }

    private var rowBackground: Color {
        if isFocused { return Color.accentColor.opacity(0.1) }
        return Color.primary.opacity(isHovering ? 0.06 : 0.03)
    }
}
